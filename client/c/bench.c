/*
 * Run using `./bench -h localhost -p 6969 -n 1000`
 */

#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define DEFAULT_SERVER_IP "127.0.0.1"
#define DEFAULT_SERVER_PORT 6969

// Command IDs
#define CMD_SET 0
#define CMD_GET 1
#define CMD_DEL 2

// for formatting
static const char *cmd_names[] = {"set", "get", "del"};

static double time_diff_ms(struct timeval start, struct timeval end) {
  return (end.tv_sec - start.tv_sec) * 1000.0 +
         (end.tv_usec - start.tv_usec) / 1000.0;
}

static void run_cli_op(const char *host, int port, const char *cmd,
                       const char *key, const char *val) {
  char callbuf[512];
  if (val) {
    snprintf(callbuf, sizeof(callbuf),
             "./client -h %s -p %d %s %s %s > /dev/null 2>&1", host, port, cmd,
             key, val);
  } else {
    snprintf(callbuf, sizeof(callbuf),
             "./client -h %s -p %d %s %s > /dev/null 2>&1", host, port, cmd,
             key);
  }

  system(callbuf);
}

static void benchmark(const char *host, int port, int cmd_id, int n) {
  char key[64], val[64];
  struct timeval t0, t1;
  const char *cmdstr = cmd_names[cmd_id];

  // Warm-up
  for (int i = 0; i < 10; i++) {
    snprintf(key, sizeof(key), "key%d", i);
    if (cmd_id == CMD_SET) {
      snprintf(val, sizeof(val), "value%d", i);
      run_cli_op(host, port, cmdstr, key, val);
    } else {
      run_cli_op(host, port, cmdstr, key, NULL);
    }
  }

  gettimeofday(&t0, NULL);
  for (int i = 0; i < n; i++) {
    snprintf(key, sizeof(key), "key%d", i);
    if (cmd_id == CMD_SET) {
      snprintf(val, sizeof(val), "value%d", i);
      run_cli_op(host, port, cmdstr, key, val);
    } else {
      run_cli_op(host, port, cmdstr, key, NULL);
    }
  }
  gettimeofday(&t1, NULL);

  double ms = time_diff_ms(t0, t1);
  printf("CMD_%s: %d ops in %.2f ms (%.2f ops/sec, avg %.2f ms/op)\n", cmdstr,
         n, ms, n / (ms / 1000.0), ms / n);
}

int main(int argc, char **argv) {
  char *host = NULL;
  int port = DEFAULT_SERVER_PORT;
  int n = 1000;
  int opt;

  while ((opt = getopt(argc, argv, "h:p:n:")) != -1) {
    switch (opt) {
    case 'h':
      host = optarg;
      break;
    case 'p':
      port = atoi(optarg);
      break;
    case 'n':
      n = atoi(optarg);
      break;
    default:
      fprintf(stderr, "Usage: %s -h server_ip [-p port] [-n ops]\n", argv[0]);
      exit(EXIT_FAILURE);
    }
  }
  if (!host) {
    fprintf(stderr, "Error: server IP is required (-h)\n");
    exit(EXIT_FAILURE);
  }

  printf("Benchmarking against %s:%d with %d ops per command\n", host, port, n);
  benchmark(host, port, CMD_SET, n);
  benchmark(host, port, CMD_GET, n);
  benchmark(host, port, CMD_DEL, n);
  return 0;
}
