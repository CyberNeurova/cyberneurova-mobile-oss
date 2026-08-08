/* Smallest thing that proves a BUNDLED tool really runs on a Play-targetSdk
 * build: a multicall binary, dispatching on argv[0] exactly like busybox. */
#include <stdio.h>
#include <string.h>

static const char *base(const char *p) {
  const char *s = strrchr(p, '/');
  return s ? s + 1 : p;
}

int main(int argc, char **argv) {
  const char *me = base(argc > 0 ? argv[0] : "cntool");
  if (!strcmp(me, "cn-hello")) { puts("BUNDLED_TOOL_OK"); return 0; }
  if (!strcmp(me, "cn-arch"))  { puts("aarch64"); return 0; }
  printf("cntool: multicall binary. applets: cn-hello cn-arch (argv[0]=%s)\n", me);
  return 0;
}
