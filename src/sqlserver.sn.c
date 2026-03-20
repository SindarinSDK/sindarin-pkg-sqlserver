/* ==============================================================================
 * sindarin-pkg-sqlserver/src/sqlserver.sn.c — SQL Server client implementation
 * ==============================================================================
 * Implements SqlServerConn, SqlServerStmt, and SqlServerRow via the FreeTDS
 * db-lib C API (sybdb.h).
 *
 * Row data is copied out of the DBPROCESS result set into heap arrays at query
 * time using dbconvert() to normalise all column types to strings. This lets
 * the caller keep rows after the next dbresults/dbcmd call.
 *
 * Prepared statements are implemented by storing the SQL template with ?
 * placeholders and an array of pre-formatted parameter values. On exec/query
 * the parameters are substituted inline: strings are escaped ('' doubling)
 * and wrapped in N'...'; integers and floats are formatted as numeric literals;
 * NULLs become the SQL NULL keyword.
 * ============================================================================== */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include <sybdb.h>

/* ============================================================================
 * Type Definitions
 * ============================================================================ */

typedef __sn__SqlServerConn  RtSqlServerConn;
typedef __sn__SqlServerStmt  RtSqlServerStmt;
typedef __sn__SqlServerRow   RtSqlServerRow;

/* ============================================================================
 * Global State — FreeTDS init and last error buffer
 * ============================================================================ */

static int  g_dbinit_done = 0;
static char g_last_error[4096] = "";

static int sql_err_handler(DBPROCESS *dbproc, int severity, int dberr,
                            int oserr, char *dberrstr, char *oserrstr)
{
    (void)dbproc; (void)severity; (void)oserr; (void)oserrstr;
    /* SYBESMSG (20018) fires after the msg handler and carries only a generic
     * "General SQL Server error: Check messages from the SQL Server" string.
     * Only update g_last_error from the err handler when the msg handler has
     * not already captured a more specific message. */
    if (dberr == SYBESMSG) return INT_CANCEL;
    if (dberrstr && *dberrstr && g_last_error[0] == '\0')
        snprintf(g_last_error, sizeof(g_last_error), "%s", dberrstr);
    return INT_CANCEL;
}

static int sql_msg_handler(DBPROCESS *dbproc, DBINT msgno, int msgstate,
                            int severity, char *msgtext, char *srvname,
                            char *procname, int line)
{
    (void)dbproc; (void)msgstate; (void)srvname; (void)procname; (void)line;
    /* Capture non-informational messages (severity > 0) as last error and
     * always print them to stderr so CI logs show the actual SQL Server text. */
    if (severity > 0 && msgtext && *msgtext) {
        fprintf(stderr, "sqlserver: msg (no=%d sev=%d): %s\n",
                (int)msgno, severity, msgtext);
        snprintf(g_last_error, sizeof(g_last_error), "%s", msgtext);
    }
    return 0;
}

static void ensure_dbinit(void)
{
    if (g_dbinit_done) return;
    if (dbinit() == FAIL) {
        fprintf(stderr, "sqlserver: dbinit() failed\n");
        exit(1);
    }
    dberrhandle(sql_err_handler);
    dbmsghandle(sql_msg_handler);
    g_dbinit_done = 1;
}

/* ============================================================================
 * DSN Parsing — "server=host:port;database=db;user=sa;password=pass"
 * ============================================================================ */

static void parse_conn_str(const char *conn_str,
                            char *server,   size_t server_sz,
                            char *database, size_t db_sz,
                            char *user,     size_t user_sz,
                            char *password, size_t pass_sz)
{
    char buf[4096];
    strncpy(buf, conn_str, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char *saveptr = NULL;
    char *tok = strtok_r(buf, ";", &saveptr);
    while (tok) {
        char *eq = strchr(tok, '=');
        if (eq) {
            *eq = '\0';
            const char *key = tok;
            const char *val = eq + 1;
            if      (strcmp(key, "server")   == 0) strncpy(server,   val, server_sz - 1);
            else if (strcmp(key, "database") == 0) strncpy(database, val, db_sz     - 1);
            else if (strcmp(key, "user")     == 0) strncpy(user,     val, user_sz   - 1);
            else if (strcmp(key, "password") == 0) strncpy(password, val, pass_sz   - 1);
        }
        tok = strtok_r(NULL, ";", &saveptr);
    }
}

/* ============================================================================
 * Row Building — copy column data out of DBPROCESS before next dbresults call
 * ============================================================================ */

#define DBPROC(c) ((DBPROCESS *)(uintptr_t)(c)->db_ptr)

static void cleanup_sql_row_elem(void *p)
{
    RtSqlServerRow *row = (RtSqlServerRow *)p;
    int count = (int)row->col_count;

    char **names  = (char **)(uintptr_t)row->col_names;
    char **values = (char **)(uintptr_t)row->col_values;
    bool  *nulls  = (bool  *)(uintptr_t)row->col_nulls;

    if (names) {
        for (int i = 0; i < count; i++) free(names[i]);
        free(names);
    }
    if (values) {
        for (int i = 0; i < count; i++) free(values[i]);
        free(values);
    }
    free(nulls);
}

static RtSqlServerRow build_row(DBPROCESS *dbproc, int ncols)
{
    RtSqlServerRow row = {0};
    row.col_count = (long long)ncols;

    char **names  = (char **)calloc((size_t)ncols, sizeof(char *));
    char **values = (char **)calloc((size_t)ncols, sizeof(char *));
    bool  *nulls  = (bool  *)calloc((size_t)ncols, sizeof(bool));

    if (!names || !values || !nulls) {
        fprintf(stderr, "sqlserver: build_row: allocation failed\n");
        exit(1);
    }

    for (int i = 1; i <= ncols; i++) {
        const char *colname = dbcolname(dbproc, i);
        names[i - 1] = strdup(colname ? colname : "");

        BYTE *data = dbdata(dbproc, i);
        if (data == NULL) {
            nulls[i - 1]  = true;
            values[i - 1] = NULL;
        } else {
            nulls[i - 1] = false;
            int  col_type = dbcoltype(dbproc, i);
            int  data_len = dbdatlen(dbproc, i);
            char buf[4096] = "";
            int  len = dbconvert(dbproc, col_type, data, (DBINT)data_len,
                                 SYBCHAR, (BYTE *)buf, (DBINT)(sizeof(buf) - 1));
            if (len < 0) len = 0;
            buf[len] = '\0';
            /* Trim trailing spaces that SYBCHAR padding sometimes adds */
            while (len > 0 && buf[len - 1] == ' ') buf[--len] = '\0';
            values[i - 1] = strdup(buf);
        }
    }

    row.col_names  = (long long)(uintptr_t)names;
    row.col_values = (long long)(uintptr_t)values;
    row.col_nulls  = (long long)(uintptr_t)nulls;
    return row;
}

static SnArray *collect_rows(DBPROCESS *dbproc)
{
    SnArray *arr = sn_array_new(sizeof(RtSqlServerRow), 16);
    arr->elem_tag     = SN_TAG_STRUCT;
    arr->elem_release = cleanup_sql_row_elem;

    RETCODE rc;
    while ((rc = dbresults(dbproc)) != NO_MORE_RESULTS) {
        if (rc == FAIL) break;
        int ncols = dbnumcols(dbproc);
        RETCODE row_rc;
        while ((row_rc = dbnextrow(dbproc)) != NO_MORE_ROWS) {
            if (row_rc == FAIL) break;
            RtSqlServerRow row = build_row(dbproc, ncols);
            sn_array_push(arr, &row);
        }
    }
    return arr;
}

/* ============================================================================
 * SqlServerRow Accessors
 * ============================================================================ */

static int find_col(RtSqlServerRow *row, const char *col)
{
    char **names = (char **)(uintptr_t)row->col_names;
    int count = (int)row->col_count;
    for (int i = 0; i < count; i++) {
        if (names[i] && strcmp(names[i], col) == 0)
            return i;
    }
    return -1;
}

char *sn_sql_row_get_string(__sn__SqlServerRow *row, char *col)
{
    if (!row || !col) return strdup("");
    int idx = find_col(row, col);
    if (idx < 0) return strdup("");
    bool *nulls = (bool *)(uintptr_t)row->col_nulls;
    if (nulls[idx]) return strdup("");
    char **values = (char **)(uintptr_t)row->col_values;
    return strdup(values[idx] ? values[idx] : "");
}

long long sn_sql_row_get_int(__sn__SqlServerRow *row, char *col)
{
    if (!row || !col) return 0;
    int idx = find_col(row, col);
    if (idx < 0) return 0;
    bool *nulls = (bool *)(uintptr_t)row->col_nulls;
    if (nulls[idx]) return 0;
    char **values = (char **)(uintptr_t)row->col_values;
    if (!values[idx]) return 0;
    return (long long)strtoll(values[idx], NULL, 10);
}

double sn_sql_row_get_float(__sn__SqlServerRow *row, char *col)
{
    if (!row || !col) return 0.0;
    int idx = find_col(row, col);
    if (idx < 0) return 0.0;
    bool *nulls = (bool *)(uintptr_t)row->col_nulls;
    if (nulls[idx]) return 0.0;
    char **values = (char **)(uintptr_t)row->col_values;
    if (!values[idx]) return 0.0;
    return strtod(values[idx], NULL);
}

bool sn_sql_row_is_null(__sn__SqlServerRow *row, char *col)
{
    if (!row || !col) return true;
    int idx = find_col(row, col);
    if (idx < 0) return true;
    bool *nulls = (bool *)(uintptr_t)row->col_nulls;
    return nulls[idx];
}

long long sn_sql_row_column_count(__sn__SqlServerRow *row)
{
    if (!row) return 0;
    return row->col_count;
}

char *sn_sql_row_column_name(__sn__SqlServerRow *row, long long index)
{
    if (!row || index < 0 || index >= row->col_count) return strdup("");
    char **names = (char **)(uintptr_t)row->col_names;
    return strdup(names[index] ? names[index] : "");
}

/* ============================================================================
 * SqlServerConn
 * ============================================================================ */

RtSqlServerConn *sn_sql_conn_connect(char *conn_str)
{
    if (!conn_str) {
        fprintf(stderr, "SqlServerConn.connect: connStr is NULL\n");
        exit(1);
    }

    ensure_dbinit();

    char server[256]   = "localhost:1433";
    char database[256] = "";
    char user[256]     = "";
    char password[256] = "";

    parse_conn_str(conn_str,
                   server,   sizeof(server),
                   database, sizeof(database),
                   user,     sizeof(user),
                   password, sizeof(password));

    LOGINREC *login = dblogin();
    if (!login) {
        fprintf(stderr, "SqlServerConn.connect: dblogin() failed\n");
        exit(1);
    }

    if (user[0])     DBSETLUSER(login, user);
    if (password[0]) DBSETLPWD(login, password);
    DBSETLAPP(login, "sindarin");

    DBPROCESS *dbproc = dbopen(login, server);
    dbloginfree(login);

    if (!dbproc) {
        fprintf(stderr, "SqlServerConn.connect: dbopen(%s) failed: %s\n",
                server, g_last_error);
        exit(1);
    }

    if (database[0] && dbuse(dbproc, database) == FAIL) {
        fprintf(stderr, "SqlServerConn.connect: dbuse(%s) failed: %s\n",
                database, g_last_error);
        dbclose(dbproc);
        exit(1);
    }

    RtSqlServerConn *c = (RtSqlServerConn *)calloc(1, sizeof(RtSqlServerConn));
    if (!c) {
        fprintf(stderr, "SqlServerConn.connect: allocation failed\n");
        dbclose(dbproc);
        exit(1);
    }
    c->db_ptr = (long long)(uintptr_t)dbproc;
    return c;
}

void sn_sql_conn_exec(RtSqlServerConn *c, char *sql)
{
    if (!c || !sql) return;
    DBPROCESS *dbproc = DBPROC(c);
    g_last_error[0] = '\0';

    if (dbcmd(dbproc, sql) == FAIL) {
        fprintf(stderr, "sqlserver: exec: dbcmd failed\n");
        exit(1);
    }
    if (dbsqlexec(dbproc) == FAIL) {
        fprintf(stderr, "sqlserver: exec: dbsqlexec failed: %s\n", g_last_error);
        exit(1);
    }

    /* Drain all result sets */
    RETCODE rc;
    while ((rc = dbresults(dbproc)) != NO_MORE_RESULTS) {
        if (rc == FAIL) break;
        while (dbnextrow(dbproc) != NO_MORE_ROWS) {}
    }
}

SnArray *sn_sql_conn_query(RtSqlServerConn *c, char *sql)
{
    if (!c || !sql) return sn_array_new(sizeof(RtSqlServerRow), 0);
    DBPROCESS *dbproc = DBPROC(c);
    g_last_error[0] = '\0';

    if (dbcmd(dbproc, sql) == FAIL) {
        fprintf(stderr, "sqlserver: query: dbcmd failed\n");
        exit(1);
    }
    if (dbsqlexec(dbproc) == FAIL) {
        fprintf(stderr, "sqlserver: query: dbsqlexec failed: %s\n", g_last_error);
        exit(1);
    }

    return collect_rows(dbproc);
}

RtSqlServerStmt *sn_sql_conn_prepare(RtSqlServerConn *c, char *name, char *sql)
{
    (void)name; /* name is kept for API symmetry with postgres; db-lib has no server-side prepare */
    if (!c || !sql) {
        fprintf(stderr, "SqlServerConn.prepare: NULL argument\n");
        exit(1);
    }

    /* Count ? placeholders */
    int param_count = 0;
    for (const char *p = sql; *p; p++) {
        if (*p == '?') param_count++;
    }

    RtSqlServerStmt *s = (RtSqlServerStmt *)calloc(1, sizeof(RtSqlServerStmt));
    if (!s) {
        fprintf(stderr, "SqlServerConn.prepare: allocation failed\n");
        exit(1);
    }
    s->db_ptr       = c->db_ptr;
    s->sql_template = (uint8_t *)strdup(sql);
    s->param_count  = (long long)param_count;

    if (param_count > 0) {
        char **vals  = (char **)calloc((size_t)param_count, sizeof(char *));
        bool  *nulls = (bool  *)calloc((size_t)param_count, sizeof(bool));
        if (!vals || !nulls) {
            fprintf(stderr, "SqlServerConn.prepare: param allocation failed\n");
            exit(1);
        }
        for (int i = 0; i < param_count; i++) nulls[i] = true;
        s->param_values = (long long)(uintptr_t)vals;
        s->param_nulls  = (long long)(uintptr_t)nulls;
    }

    return s;
}

char *sn_sql_conn_last_error(RtSqlServerConn *c)
{
    (void)c;
    return strdup(g_last_error);
}

void sn_sql_conn_dispose(RtSqlServerConn *c)
{
    if (!c) return;
    DBPROCESS *dbproc = DBPROC(c);
    if (dbproc) dbclose(dbproc);
    c->db_ptr = 0;
}

/* ============================================================================
 * SqlServerStmt — parameter binding and SQL construction
 * ============================================================================ */

#define STMT_DBPROC(s) ((DBPROCESS *)(uintptr_t)(s)->db_ptr)
#define STMT_TMPL(s)   ((const char *)(s)->sql_template)
#define STMT_VALS(s)   ((char **)(uintptr_t)(s)->param_values)
#define STMT_NULLS(s)  ((bool  *)(uintptr_t)(s)->param_nulls)

/* Format a string value as a T-SQL N'...' literal with escaped single quotes */
static char *format_string_param(const char *s)
{
    size_t len = strlen(s);
    size_t quote_count = 0;
    for (const char *p = s; *p; p++)
        if (*p == '\'') quote_count++;

    /* N' + content (with doubled quotes) + ' + NUL */
    char *out = (char *)malloc(3 + len + quote_count + 1);
    if (!out) {
        fprintf(stderr, "sqlserver: format_string_param: allocation failed\n");
        exit(1);
    }
    char *w = out;
    *w++ = 'N'; *w++ = '\'';
    for (const char *p = s; *p; p++) {
        if (*p == '\'') *w++ = '\''; /* escape: ' → '' */
        *w++ = *p;
    }
    *w++ = '\''; *w = '\0';
    return out;
}

static void stmt_set_param(RtSqlServerStmt *s, int index, char *value, bool is_null)
{
    if (!s || index < 1 || index > (int)s->param_count) {
        fprintf(stderr, "SqlServerStmt: bind index %d out of range (1..%lld)\n",
                index, s ? s->param_count : 0);
        exit(1);
    }
    int    i     = index - 1;
    char **vals  = STMT_VALS(s);
    bool  *nulls = STMT_NULLS(s);
    free(vals[i]);
    vals[i]  = value;
    nulls[i] = is_null;
}

void sn_sql_stmt_bind_string(RtSqlServerStmt *s, long long index, char *value)
{
    if (value == NULL) {
        stmt_set_param(s, (int)index, NULL, true);
    } else {
        stmt_set_param(s, (int)index, format_string_param(value), false);
    }
}

void sn_sql_stmt_bind_int(RtSqlServerStmt *s, long long index, long long value)
{
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", value);
    stmt_set_param(s, (int)index, strdup(buf), false);
}

void sn_sql_stmt_bind_float(RtSqlServerStmt *s, long long index, double value)
{
    char buf[64];
    snprintf(buf, sizeof(buf), "%.17g", value);
    stmt_set_param(s, (int)index, strdup(buf), false);
}

void sn_sql_stmt_bind_null(RtSqlServerStmt *s, long long index)
{
    stmt_set_param(s, (int)index, NULL, true);
}

/* Build final SQL by substituting ? with bound parameter values */
static char *build_sql(RtSqlServerStmt *s)
{
    const char *tmpl   = STMT_TMPL(s);
    char      **vals   = STMT_VALS(s);
    bool       *nulls  = STMT_NULLS(s);
    int         pcount = (int)s->param_count;

    /* First pass: calculate required buffer size */
    size_t total  = 0;
    int    pidx   = 0;
    for (const char *p = tmpl; *p; p++) {
        if (*p == '?') {
            if (pidx < pcount) {
                if (nulls[pidx] || !vals[pidx])
                    total += 4; /* NULL */
                else
                    total += strlen(vals[pidx]);
                pidx++;
            } else {
                total += 1;
            }
        } else {
            total += 1;
        }
    }

    char *out = (char *)malloc(total + 1);
    if (!out) {
        fprintf(stderr, "sqlserver: build_sql: allocation failed\n");
        exit(1);
    }

    /* Second pass: write the SQL */
    char *w = out;
    pidx = 0;
    for (const char *p = tmpl; *p; p++) {
        if (*p == '?') {
            if (pidx < pcount) {
                if (nulls[pidx] || !vals[pidx]) {
                    memcpy(w, "NULL", 4); w += 4;
                } else {
                    size_t len = strlen(vals[pidx]);
                    memcpy(w, vals[pidx], len); w += len;
                }
                pidx++;
            } else {
                *w++ = '?';
            }
        } else {
            *w++ = *p;
        }
    }
    *w = '\0';
    return out;
}

static void stmt_exec_internal(RtSqlServerStmt *s)
{
    char *sql = build_sql(s);
    DBPROCESS *dbproc = STMT_DBPROC(s);
    g_last_error[0] = '\0';

    if (dbcmd(dbproc, sql) == FAIL) {
        free(sql);
        fprintf(stderr, "sqlserver: stmt exec: dbcmd failed\n");
        exit(1);
    }
    free(sql);

    if (dbsqlexec(dbproc) == FAIL) {
        fprintf(stderr, "sqlserver: stmt exec: dbsqlexec failed: %s\n", g_last_error);
        exit(1);
    }
}

void sn_sql_stmt_exec(RtSqlServerStmt *s)
{
    if (!s) return;
    stmt_exec_internal(s);

    /* Drain all result sets */
    RETCODE rc;
    while ((rc = dbresults(STMT_DBPROC(s))) != NO_MORE_RESULTS) {
        if (rc == FAIL) break;
        while (dbnextrow(STMT_DBPROC(s)) != NO_MORE_ROWS) {}
    }
}

SnArray *sn_sql_stmt_query(RtSqlServerStmt *s)
{
    if (!s) return sn_array_new(sizeof(RtSqlServerRow), 0);
    stmt_exec_internal(s);
    return collect_rows(STMT_DBPROC(s));
}

void sn_sql_stmt_reset(RtSqlServerStmt *s)
{
    if (!s) return;
    int    n    = (int)s->param_count;
    char **vals = STMT_VALS(s);
    bool  *nulls = STMT_NULLS(s);
    for (int i = 0; i < n; i++) {
        free(vals[i]);
        vals[i]  = NULL;
        nulls[i] = true;
    }
}

void sn_sql_stmt_dispose(RtSqlServerStmt *s)
{
    if (!s) return;
    int    n    = (int)s->param_count;
    char **vals = STMT_VALS(s);
    if (vals) {
        for (int i = 0; i < n; i++) free(vals[i]);
        free(vals);
    }
    free((void *)(uintptr_t)s->param_nulls);
    free((void *)s->sql_template);
    s->db_ptr       = 0;
    s->sql_template = NULL;
    s->param_values = 0;
    s->param_nulls  = 0;
}
