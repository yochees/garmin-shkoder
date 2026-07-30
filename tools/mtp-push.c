// Push a file to an explicit MTP folder + storage.
//
// libmtp's own mtp-sendfile asks the device to suggest a storage id for the
// parent folder, which the fenix 8 refuses ("could not get storage id from
// parent id"). Setting both ids ourselves works.
//
//   cc -o mtp-push tools/mtp-push.c $(pkg-config --cflags --libs libmtp)
//   ./mtp-push <local file> <remote name> [parent_id] [storage_id]

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <libmtp.h>

#define GARMIN_APPS_ID 16777226
#define INTERNAL_STORAGE 0x00020001

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <local file> <remote name> [parent_id] [storage_id]\n", argv[0]);
        return 2;
    }

    const char *local = argv[1];
    const char *remote = argv[2];
    uint32_t parent = (argc > 3) ? (uint32_t)strtoul(argv[3], NULL, 0) : GARMIN_APPS_ID;
    uint32_t storage = (argc > 4) ? (uint32_t)strtoul(argv[4], NULL, 0) : INTERNAL_STORAGE;

    struct stat st;
    if (stat(local, &st) != 0) {
        perror(local);
        return 1;
    }

    LIBMTP_Init();
    LIBMTP_mtpdevice_t *device = LIBMTP_Get_First_Device();
    if (device == NULL) {
        fprintf(stderr, "no MTP device found\n");
        return 1;
    }

    LIBMTP_file_t *f = LIBMTP_new_file_t();
    f->filename = strdup(remote);
    f->filesize = (uint64_t)st.st_size;
    f->filetype = LIBMTP_FILETYPE_UNKNOWN;
    f->parent_id = parent;
    f->storage_id = storage;

    int rc = LIBMTP_Send_File_From_File(device, local, f, NULL, NULL);
    if (rc != 0) {
        LIBMTP_Dump_Errorstack(device);
        LIBMTP_Clear_Errorstack(device);
    } else {
        printf("sent %s -> parent=%u storage=0x%08x (%lld bytes)\n",
               remote, parent, storage, (long long)st.st_size);
    }

    LIBMTP_destroy_file_t(f);
    LIBMTP_Release_Device(device);
    return rc == 0 ? 0 : 1;
}
