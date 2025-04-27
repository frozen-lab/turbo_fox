#include <arpa/inet.h>
#include <errno.h>
#include <getopt.h>
#include <netinet/in.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h> // for struct tm, localtime_r, strftime
#include <unistd.h>

#define DEFAULT_SERVER_IP "127.0.0.1"
#define DEFAULT_SERVER_PORT 6969
#define MAX_RESPONSE_SIZE (10 * 1024 * 1024)

// Command IDs
#define CMD_SET 0
#define CMD_GET 1
#define CMD_DEL 2

// Log levels
typedef enum { LOG_DEBUG = 0, LOG_INFO, LOG_WARN, LOG_ERROR } log_level_t;
static log_level_t client_log_level = LOG_INFO;
static const char *level_names[] = {"DEBUG", "INFO", "WARN", "ERROR"};

static void log_msg(log_level_t lvl, const char *fmt, ...) {
  if (lvl < client_log_level)
    return;
  struct timeval tv;
  gettimeofday(&tv, NULL);
  time_t sec = tv.tv_sec;
  struct tm tm;
  localtime_r(&sec, &tm);
  char timebuf[64];
  strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", &tm);
  printf("%s.%03ld [%s] ", timebuf, tv.tv_usec / 1000, level_names[lvl]);
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
  printf("\n");
}

static void die(const char *msg) {
  log_msg(LOG_ERROR, "%s: %s", msg, strerror(errno));
  exit(EXIT_FAILURE);
}

static ssize_t read_full(int fd, void *buf, size_t n) {
  size_t left = n;
  char *p = buf;
  while (left) {
    ssize_t r = read(fd, p, left);
    if (r < 0) {
      if (errno == EINTR)
        continue;
      return -1;
    }
    if (r == 0)
      break;
    left -= r;
    p += r;
  }
  return (n - left);
}

static ssize_t write_full(int fd, const void *buf, size_t n) {
  size_t left = n;
  const char *p = buf;
  while (left) {
    ssize_t w = write(fd, p, left);
    if (w < 0) {
      if (errno == EINTR)
        continue;
      return -1;
    }
    left -= w;
    p += w;
  }
  return n;
}

static void send_request(int fd, uint8_t cmd, const uint8_t *key,
                         uint32_t key_len, const uint8_t *val,
                         uint32_t val_len) {
  log_msg(LOG_DEBUG, "Sending cmd=%u, key_len=%u, val_len=%u", cmd, key_len,
          val_len);
  if (write_full(fd, &cmd, 1) != 1)
    die("write cmd");

  uint32_t nk = htonl(key_len);
  if (write_full(fd, &nk, sizeof(nk)) != sizeof(nk))
    die("write key_len");
  if (key_len && write_full(fd, key, key_len) != key_len)
    die("write key data");

  uint32_t nv = htonl(val_len);
  if (write_full(fd, &nv, sizeof(nv)) != sizeof(nv))
    die("write val_len");
  if (val_len && write_full(fd, val, val_len) != val_len)
    die("write val data");

  uint8_t resp_id;
  if (read_full(fd, &resp_id, 1) != 1)
    die("read resp_id");
  log_msg(LOG_INFO, "Received response id: %u", resp_id);

  if (resp_id == 200) {
    uint32_t nr;
    if (read_full(fd, &nr, sizeof(nr)) != sizeof(nr))
      die("read resp size");
    nr = ntohl(nr);
    if (nr > MAX_RESPONSE_SIZE)
      die("response too large");

    uint8_t *resp = malloc(nr + 1);
    if (!resp)
      die("malloc");
    if (read_full(fd, resp, nr) != nr)
      die("read resp data");
    resp[nr] = '\0';
    printf("Value: %s\n", resp);
    free(resp);
  }
}

static void usage(const char *prog) {
  fprintf(stderr,
          "Usage: %s [-h host] [-p port] [-l level] <cmd> <key> [value]\n"
          "  level: debug, info, warn, error\n"
          "  cmd: set <key> <value> | get <key> | del <key>\n",
          prog);
  exit(EXIT_FAILURE);
}

int main(int argc, char **argv) {
  char *host = DEFAULT_SERVER_IP;
  int port = DEFAULT_SERVER_PORT;
  int opt;

  while ((opt = getopt(argc, argv, "h:p:l:")) != -1) {
    switch (opt) {
    case 'h':
      host = optarg;
      break;
    case 'p':
      port = atoi(optarg);
      break;
    case 'l':
      if (strcmp(optarg, "debug") == 0)
        client_log_level = LOG_DEBUG;
      else if (strcmp(optarg, "info") == 0)
        client_log_level = LOG_INFO;
      else if (strcmp(optarg, "warn") == 0)
        client_log_level = LOG_WARN;
      else if (strcmp(optarg, "error") == 0)
        client_log_level = LOG_ERROR;
      else
        die("invalid log level");
      break;
    default:
      usage(argv[0]);
    }
  }

  if (optind >= argc)
    usage(argv[0]);

  const char *cmdstr = argv[optind++];
  uint8_t cmd;
  const char *key = NULL, *val = NULL;
  uint32_t key_len = 0, val_len = 0;

  if (strcmp(cmdstr, "set") == 0) {
    if (optind + 1 >= argc)
      usage(argv[0]);
    cmd = CMD_SET;
    key = argv[optind++];
    key_len = strlen(key);
    val = argv[optind++];
    val_len = strlen(val);
  } else if (strcmp(cmdstr, "get") == 0) {
    if (optind >= argc)
      usage(argv[0]);
    cmd = CMD_GET;
    key = argv[optind++];
    key_len = strlen(key);
  } else if (strcmp(cmdstr, "del") == 0) {
    if (optind >= argc)
      usage(argv[0]);
    cmd = CMD_DEL;
    key = argv[optind++];
    key_len = strlen(key);
  } else {
    usage(argv[0]);
  }

  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0)
    die("socket");

  struct sockaddr_in srv = {0};
  srv.sin_family = AF_INET;
  srv.sin_port = htons(port);
  if (inet_pton(AF_INET, host, &srv.sin_addr) != 1)
    die("inet_pton");

  if (connect(fd, (struct sockaddr *)&srv, sizeof(srv)) < 0)
    die("connect");
  send_request(fd, cmd, (uint8_t *)key, key_len, (uint8_t *)(val ? val : ""),
               val_len);
  close(fd);

  return 0;
}
