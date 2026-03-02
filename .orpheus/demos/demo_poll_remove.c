/*
 * Demo: CURL_POLL_REMOVE behavior with idle connections
 *
 * This program demonstrates that when using the multi socket interface:
 * 1. CURL_POLL_REMOVE is signaled when a transfer completes / connection goes idle
 * 2. The application must stop monitoring the socket after CURL_POLL_REMOVE
 * 3. The socketp pointer (set via curl_multi_assign) is forgotten by libcurl
 *
 * This verifies the documented behavior in CURLMOPT_SOCKETFUNCTION.
 *
 * Build:
 *   gcc -o demo_poll_remove demo_poll_remove.c \
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
 *   Then: ./demo_poll_remove
 *
 * Expected output shows:
 *   - socket_cb called with CURL_POLL_OUT (connect phase)
 *   - socketp assigned via curl_multi_assign (marker=42)
 *   - socket_cb called with CURL_POLL_REMOVE, socketp reported then forgotten
 *   - socket re-added with socketp=(nil), confirming libcurl forgot the pointer
 *   - Transfer completes with HTTP 200
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>
#include <sys/select.h>

/* Track sockets for our select() loop */
#define MAX_SOCKETS 16
static curl_socket_t watched[MAX_SOCKETS];
static int watch_what[MAX_SOCKETS];
static int nsockets = 0;

static int socket_callback(CURL *easy, curl_socket_t s, int what,
                           void *clientp, void *socketp)
{
  const char *whatstr;
  switch(what) {
  case CURL_POLL_IN:     whatstr = "CURL_POLL_IN"; break;
  case CURL_POLL_OUT:    whatstr = "CURL_POLL_OUT"; break;
  case CURL_POLL_INOUT:  whatstr = "CURL_POLL_INOUT"; break;
  case CURL_POLL_REMOVE: whatstr = "CURL_POLL_REMOVE"; break;
  default:               whatstr = "UNKNOWN"; break;
  }

  printf("[socket_cb] socket=%d action=%s socketp=%p\n",
         (int)s, whatstr, socketp);

  if(what == CURL_POLL_REMOVE) {
    printf("[socket_cb] >>> CURL_POLL_REMOVE received for socket %d\n", (int)s);
    printf("[socket_cb] >>> Application should STOP monitoring this socket\n");
    printf("[socket_cb] >>> socketp pointer (%p) is now forgotten by libcurl\n",
           socketp);
    /* Remove from our watch list */
    for(int i = 0; i < nsockets; i++) {
      if(watched[i] == s) {
        watched[i] = watched[nsockets - 1];
        watch_what[i] = watch_what[nsockets - 1];
        nsockets--;
        break;
      }
    }
  }
  else {
    /* Add or update socket in our watch list */
    int found = 0;
    for(int i = 0; i < nsockets; i++) {
      if(watched[i] == s) {
        watch_what[i] = what;
        found = 1;
        break;
      }
    }
    if(!found && nsockets < MAX_SOCKETS) {
      watched[nsockets] = s;
      watch_what[nsockets] = what;
      nsockets++;

      /* Demo: assign a custom pointer to this socket */
      CURLM *multi = (CURLM *)clientp;
      int *marker = malloc(sizeof(int));
      *marker = 42;
      curl_multi_assign(multi, s, marker);
      printf("[socket_cb] >>> Assigned socketp marker=%d via curl_multi_assign\n",
             *marker);
    }
  }

  return 0;
}

static long timeout_ms_global = -1;

static int timer_callback(CURLM *multi, long timeout_ms, void *clientp)
{
  timeout_ms_global = timeout_ms;
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
  CURL *easy;
  int running = 0;
  CURLMcode mc;

  curl_global_init(CURL_GLOBAL_ALL);
  multi = curl_multi_init();

  curl_multi_setopt(multi, CURLMOPT_SOCKETFUNCTION, socket_callback);
  curl_multi_setopt(multi, CURLMOPT_SOCKETDATA, multi);
  curl_multi_setopt(multi, CURLMOPT_TIMERFUNCTION, timer_callback);

  easy = curl_easy_init();
  curl_easy_setopt(easy, CURLOPT_URL, "http://localhost:8888/");
  curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, write_callback);

  curl_multi_add_handle(multi, easy);

  printf("=== Starting transfer ===\n");

  /* Kick off */
  mc = curl_multi_socket_action(multi, CURL_SOCKET_TIMEOUT, 0, &running);

  while(running > 0) {
    fd_set fdread, fdwrite, fdexcep;
    int maxfd = -1;
    struct timeval tv;

    FD_ZERO(&fdread);
    FD_ZERO(&fdwrite);
    FD_ZERO(&fdexcep);

    for(int i = 0; i < nsockets; i++) {
      if(watch_what[i] & CURL_POLL_IN) {
        FD_SET(watched[i], &fdread);
        if((int)watched[i] > maxfd) maxfd = (int)watched[i];
      }
      if(watch_what[i] & CURL_POLL_OUT) {
        FD_SET(watched[i], &fdwrite);
        if((int)watched[i] > maxfd) maxfd = (int)watched[i];
      }
    }

    if(timeout_ms_global >= 0) {
      tv.tv_sec = timeout_ms_global / 1000;
      tv.tv_usec = (timeout_ms_global % 1000) * 1000;
    }
    else {
      tv.tv_sec = 1;
      tv.tv_usec = 0;
    }

    int rc = select(maxfd + 1, &fdread, &fdwrite, &fdexcep, &tv);

    if(rc > 0) {
      for(int i = 0; i < nsockets; i++) {
        int ev = 0;
        if(FD_ISSET(watched[i], &fdread)) ev |= CURL_CSELECT_IN;
        if(FD_ISSET(watched[i], &fdwrite)) ev |= CURL_CSELECT_OUT;
        if(ev) {
          mc = curl_multi_socket_action(multi, watched[i], ev, &running);
        }
      }
    }
    else {
      mc = curl_multi_socket_action(multi, CURL_SOCKET_TIMEOUT, 0, &running);
    }
  }

  /* Read result */
  {
    CURLMsg *msg;
    int msgs_left;
    while((msg = curl_multi_info_read(multi, &msgs_left))) {
      if(msg->msg == CURLMSG_DONE) {
        long http_code = 0;
        curl_easy_getinfo(msg->easy_handle, CURLINFO_RESPONSE_CODE,
                          &http_code);
        printf("[main] Transfer completed: HTTP %ld, result=%d\n",
               http_code, msg->data.result);
      }
    }
  }

  printf("\n=== Transfer done, removing handle ===\n");
  printf("=== Watch for CURL_POLL_REMOVE (idle connection cleanup) ===\n\n");

  curl_multi_remove_handle(multi, easy);
  curl_easy_cleanup(easy);

  printf("\n=== Cleaning up multi handle ===\n");
  printf("=== Watch for any additional CURL_POLL_REMOVE during cleanup ===\n\n");
  curl_multi_cleanup(multi);
  curl_global_cleanup();

  printf("\n=== Done ===\n");
  return 0;
}
