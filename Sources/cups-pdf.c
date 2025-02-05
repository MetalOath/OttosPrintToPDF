#include <cups/cups.h>
#include <cups/backend.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <pwd.h>

static void copy_file(const char *src, const char *dst) {
    FILE *in = fopen(src, "rb");
    if (!in) return;
    
    FILE *out = fopen(dst, "wb");
    if (!out) {
        fclose(in);
        return;
    }
    
    char buf[4096];
    size_t n;
    
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
        fwrite(buf, 1, n, out);
    }
    
    fclose(in);
    fclose(out);
}

int main(int argc, char *argv[]) {
    if (argc == 1) {
        // No arguments - list device
        puts("file cups-pdf:/ \"Otto's Print to PDF\" \"Otto's Print to PDF\" \"MFG:Otto;CMD:PDF;\"");
        return CUPS_BACKEND_OK;
    }
    
    if (argc < 6 || argc > 7) {
        fputs("ERROR: Wrong number of arguments\n", stderr);
        return CUPS_BACKEND_FAILED;
    }
    
    // Get job info
    int job_id = atoi(argv[1]);
    const char *user = argv[2];
    const char *title = argv[3];
    int num_options = 0;
    cups_option_t *options = NULL;
    
    // Get user's home directory
    struct passwd *pwd = getpwnam(user);
    if (!pwd) {
        fputs("ERROR: Unable to get user info\n", stderr);
        return CUPS_BACKEND_FAILED;
    }
    
    // Create output filename
    char output_dir[1024];
    snprintf(output_dir, sizeof(output_dir), "%s/Documents", pwd->pw_dir);
    
    // Ensure directory exists
    mkdir(output_dir, 0755);
    
    char output_path[2048];
    snprintf(output_path, sizeof(output_path), "%s/%s.pdf", 
             output_dir, title);
    
    // Copy input file to output
    copy_file(argv[6], output_path);
    
    // Set permissions
    chown(output_path, pwd->pw_uid, pwd->pw_gid);
    chmod(output_path, 0644);
    
    return CUPS_BACKEND_OK;
}
