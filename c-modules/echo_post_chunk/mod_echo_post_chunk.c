#if CONFIG_FOR_HTTPD_TEST

<Location /echo_post_chunk>
   SetHandler echo_post_chunk
</Location>

#endif

#define APACHE_HTTPD_TEST_HANDLER echo_post_chunk_handler

#include "apache_httpd_test.h"

static int echo_post_chunk_handler(request_rec *r)
{
    int rc;
    long nrd, total = 0;
    char buff[BUFSIZ];
    const char *trailer_header;

    if (strcmp(r->handler, "echo_post_chunk")) {
        return DECLINED;
    }
    if (r->method_number != M_POST) {
        return DECLINED;
    }

    if ((rc = ap_setup_client_block(r, REQUEST_CHUNKED_DECHUNK)) != OK) {
        ap_log_error(APLOG_MARK, APLOG_ERR|APLOG_NOERRNO,
#ifdef APACHE2
                     0,
#endif /* APACHE2 */
                     r->server,
                     "[mod_echo_post_chunk] ap_setup_client_block failed: %d", rc);
        return 0;
    }

    if (!ap_should_client_block(r)) {
        return OK;
    }

    if (r->args) {
        ap_rprintf(r, "%ld:", r->remaining);
    }

    fprintf(stderr, "[mod_echo_post_chunk] going to echo %ld bytes\n",
            r->remaining);

    while ((nrd = ap_get_client_block(r, buff, sizeof(buff))) > 0) {
        fprintf(stderr,
                "[mod_echo_post_chunk] read %ld bytes (wanted %d, remaining=%ld)\n",
                nrd, sizeof(buff), r->remaining);
        total += nrd;
    }

    /* nrd < 0 is an error condition. Either the chunk size overflowed or the buffer
     * size was insufficient. We can only deduce that the request is in error.
     */
    if (nrd < 0) {
        return HTTP_BAD_REQUEST;
    }
#ifdef APACHE1
    ap_send_http_header(r);
#endif

#ifdef APACHE1
    trailer_header = ap_table_get(r->headers_in, "X-Chunk-Trailer");
#else
    trailer_header = apr_table_get(r->headers_in, "X-Chunk-Trailer");
#endif
    if (!trailer_header) {
        trailer_header = "No chunked trailer available!";
    }

    ap_rputs(trailer_header, r);

    fprintf(stderr,
            "[mod_echo_post_chunk] done reading %ld bytes, %ld bytes remain\n",
            total, r->remaining);
    
    return OK;
}

APACHE_HTTPD_TEST_MODULE(echo_post_chunk);
