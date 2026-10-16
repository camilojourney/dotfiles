/* A distinct launchd responsibility identity, not a sandbox or durability layer.
 * Build/sign into the task's private runtime directory and pin its final hash.
 * [impl->req~agent-platform.central-privacy-identity~1]
 */
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2 || argv[1][0] != '/') {
        fputs("agent-platform: an absolute exec target is required\n", stderr);
        return 64;
    }
    execv(argv[1], &argv[1]);
    const int failure = errno;
    fputs("agent-platform: could not exec configured program\n", stderr);
    return failure == ENOENT ? 127 : 126;
}
