/*
 * Demo: CURLOPT_CLOSESOCKETFUNCTION is copied from the first easy handle
 *
 * This program demonstrates that:
 * 1. The close socket callback is copied from the FIRST easy handle that
 *    creates the connection
 * 2. Changing the option on a subsequent easy handle that reuses the
 *    connection has no effect for that connection
 * 3. The callback persists even after the original easy handle is cleaned up
 *
 * This verifies the documented behavior in CURLOPT_CLOSESOCKETFUNCTION.
 *
 * Build:
 *   gcc -o demo_closesocket demo_closesocket.c \
 *     -I<curl-src>/include -L<curl-src>/lib/.libs -lcurl \
 *     -Wl,-rpath,<curl-src>/lib/.libs
 *
 * Run:
 *   Start a test HTTP server first:
 *     python3 -c "
 *     from http.server import HTTPServer, BaseHTTPRequestHandler
 *     class H(BaseHTTPRequestHandler):
 *         def do_GET(self):
 *             self.send_response(200)
 *             self.send_header('Content-Type','text/plain')
 *             self.send_header('Connection','keep-alive')
 *             body = b'Hello\n'
 *             self.send_header('Content-Length', str(len(body)))
 *             self.end_headers()
 *             self.wfile.write(body)
 *         def log_message(self, *a): pass
 *     HTTPServer(('127.0.0.1', 8888), H).serve_forever()
 *     " &
 *   Then: ./demo_closesocket
 *
 * Expected output:
 *   - Transfer 1 completes using close_cb_FIRST
 *   - Transfer 2 reuses the connection but sets close_cb_SECOND
 *   - On cleanup, close_cb_FIRST fires (not SECOND), confirming the docs
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <curl/curl.h>

static int close_cb_first(void *clientp, curl_socket_t item)
{
  printf("[close_cb_FIRST] closing socket %d (this is the FIRST callback)\n",
         (int)item);
  close(item);
  return 0;
}

static int close_cb_second(void *clientp, curl_socket_t item)
{
  printf("[close_cb_SECOND] closing socket %d (this is the SECOND callback)\n",
         (int)item);
  close(item);
  return 0;
}

static size_t write_callback(char *ptr, size_t size, size_t nmemb,
                             void *userdata)
{
  return size * nmemb;
}

int main(void)
{
  CURLM *multi;
  CURL *easy1, *easy2;
  int running = 0;
  CURLMcode mc;

  curl_global_init(CURL_GLOBAL_ALL);
  multi = curl_multi_init();

  /* First easy handle with close_cb_first */
  easy1 = curl_easy_init();
  curl_easy_setopt(easy1, CURLOPT_URL, "http://localhost:8888/");
  curl_easy_setopt(easy1, CURLOPT_WRITEFUNCTION, write_callback);
  curl_easy_setopt(easy1, CURLOPT_CLOSESOCKETFUNCTION, close_cb_first);
  curl_easy_setopt(easy1, CURLOPT_VERBOSE, 1L);

  printf("=== Transfer 1: using close_cb_FIRST ===\n");
  curl_multi_add_handle(multi, easy1);

  /* Run transfer 1 to completion */
  do {
    mc = curl_multi_perform(multi, &running);
    if(running) {
      mc = curl_multi_poll(multi, NULL, 0, 1000, NULL);
    }
  } while(running);

  /* Check result */
  {
    CURLMsg *msg;
    int msgs_left;
    while((msg = curl_multi_info_read(multi, &msgs_left))) {
      if(msg->msg == CURLMSG_DONE) {
        printf("[transfer1] completed with code %d\n", msg->data.result);
      }
    }
  }

  curl_multi_remove_handle(multi, easy1);
  curl_easy_cleanup(easy1);

  printf("\n=== Transfer 2: using close_cb_SECOND (but connection is reused) ===\n");
  printf("=== The docs say the FIRST callback should be used for this connection ===\n\n");

  /* Second easy handle with close_cb_second */
  easy2 = curl_easy_init();
  curl_easy_setopt(easy2, CURLOPT_URL, "http://localhost:8888/");
  curl_easy_setopt(easy2, CURLOPT_WRITEFUNCTION, write_callback);
  curl_easy_setopt(easy2, CURLOPT_CLOSESOCKETFUNCTION, close_cb_second);
  curl_easy_setopt(easy2, CURLOPT_VERBOSE, 1L);

  curl_multi_add_handle(multi, easy2);

  /* Run transfer 2 to completion - should reuse the connection */
  do {
    mc = curl_multi_perform(multi, &running);
    if(running) {
      mc = curl_multi_poll(multi, NULL, 0, 1000, NULL);
    }
  } while(running);

  {
    CURLMsg *msg;
    int msgs_left;
    while((msg = curl_multi_info_read(multi, &msgs_left))) {
      if(msg->msg == CURLMSG_DONE) {
        printf("[transfer2] completed with code %d\n", msg->data.result);
      }
    }
  }

  curl_multi_remove_handle(multi, easy2);
  curl_easy_cleanup(easy2);

  printf("\n=== Cleaning up multi handle - the close callback fires here ===\n");
  printf("=== Per the docs, close_cb_FIRST should be invoked (not SECOND) ===\n\n");
  curl_multi_cleanup(multi);
  curl_global_cleanup();

  printf("\n=== Done ===\n");
  return 0;
}
