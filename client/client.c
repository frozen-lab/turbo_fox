#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define MAX_RESPONSE_SIZE (10 * 1024 * 1024)

/* Command IDs */
#define CMD_SET 0
#define CMD_GET 1
#define CMD_DEL 2

static void die(const char *msg) {
  perror(msg);
  exit(EXIT_FAILURE);
}

/* read exactly n bytes or die */
static void read_full(int fd, void *buf, size_t n) {
  size_t left = n;
  char *p = buf;
  while (left) {
    ssize_t r = read(fd, p, left);
    if (r < 0)
      die("read");
    if (r == 0) {
      fprintf(stderr, "unexpected EOF\n");
      exit(EXIT_FAILURE);
    }
    left -= r;
    p += r;
  }
}

/* write exactly n bytes or die */
static void write_full(int fd, const void *buf, size_t n) {
  size_t left = n;
  const char *p = buf;
  while (left) {
    ssize_t w = write(fd, p, left);
    if (w < 0)
      die("write");
    left -= w;
    p += w;
  }
}

static void send_request(int fd, uint8_t cmd, const char *key, uint32_t key_len,
                         const char *val, uint32_t val_len) {
  // 1-byte cmd: 0=SET, 1=GET, 2=DEL
  write_full(fd, &cmd, 1);

  // 4-byte key length (network byte order)
  uint32_t nk = htonl(key_len);
  write_full(fd, &nk, sizeof(nk));

  // key data
  if (key_len)
    write_full(fd, key, key_len);

  // 4-byte val length
  uint32_t nv = htonl(val_len);
  write_full(fd, &nv, sizeof(nv));

  // value data
  if (val_len)
    write_full(fd, val, val_len);

  // Read 1-byte response ID
  uint8_t resp_id;
  read_full(fd, &resp_id, sizeof(resp_id));
  printf("response id: %u\n", resp_id);

  // For IDs 200, 201, 202, read length + message
  if (resp_id == 200 || resp_id == 201 || resp_id == 202) {
    uint32_t nr;
    read_full(fd, &nr, sizeof(nr));
    nr = ntohl(nr);
    if (nr > MAX_RESPONSE_SIZE) {
      fprintf(stderr, "response too large: %u\n", nr);
      exit(EXIT_FAILURE);
    }

    char *resp = malloc(nr + 1);
    if (!resp)
      die("malloc");
    read_full(fd, resp, nr);
    resp[nr] = '\0';

    printf("server says: %s\n", resp);
    free(resp);
  }
}

int main(void) {
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0)
    die("socket");

  struct sockaddr_in srv = {
      .sin_family = AF_INET,
      .sin_port = htons(6969),
  };
  if (inet_pton(AF_INET, "127.0.0.1", &srv.sin_addr) != 1)
    die("inet_pton");

  if (connect(fd, (struct sockaddr *)&srv, sizeof(srv)) < 0)
    die("connect");

  // Example usage:

  // 1) SET foo -> bar
  send_request(fd, CMD_SET, "foo", 3, "bar", 3);

  // 2) GET foo
  // send_request(fd, CMD_GET, "foo", 3, NULL, 0);

  // 3) DEL foo
  // send_request(fd, CMD_DEL, "foo", 3, NULL, 0);

  close(fd);
  return 0;
}
