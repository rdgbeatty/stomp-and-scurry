#include <stddef.h>
#include <stdint.h>

/* Only the Windows APIs used by the helper. No C runtime is needed. */
typedef void *Handle;
typedef struct {
    uint32_t size;
    unsigned char reserved[100];
} StartupInfo;
typedef struct {
    Handle process;
    Handle thread;
    uint32_t process_id;
    uint32_t thread_id;
} ProcessInfo;

#define API(module, result, name, arguments) \
    extern result (__attribute__((ms_abi)) *__imp_##name) arguments
#define WIN(name) __imp_##name
API(kernel32, wchar_t *, GetCommandLineW, (void));
API(shell32, wchar_t **, CommandLineToArgvW, (const wchar_t *, int *));
API(kernel32, Handle, OpenProcess, (uint32_t, int, uint32_t));
API(kernel32, uint32_t, WaitForSingleObject, (Handle, uint32_t));
API(kernel32, int, CloseHandle, (Handle));
API(kernel32, int, ReplaceFileW, (const wchar_t *, const wchar_t *, const wchar_t *, uint32_t, void *, void *));
API(kernel32, int, MoveFileExW, (const wchar_t *, const wchar_t *, uint32_t));
API(kernel32, uint32_t, GetFileAttributesW, (const wchar_t *));
API(kernel32, int, DeleteFileW, (const wchar_t *));
API(kernel32, int, CreateProcessW, (const wchar_t *, wchar_t *, void *, void *, int, uint32_t, void *,
    const wchar_t *, StartupInfo *, ProcessInfo *));
API(kernel32, int, TerminateProcess, (Handle, uint32_t));
API(kernel32, Handle, GetProcessHeap, (void));
API(kernel32, void *, HeapAlloc, (Handle, uint32_t, size_t));
API(kernel32, int, HeapFree, (Handle, uint32_t, void *));
API(kernel32, void, Sleep, (uint32_t));
API(kernel32, void, ExitProcess, (uint32_t));
API(user32, int, MessageBoxW, (Handle, const wchar_t *, const wchar_t *, uint32_t));

enum {
    WAIT_COMPLETE = 0,
    WAIT_PENDING = 258,
    SYNCHRONIZE = 0x00100000,
    MOVE_REPLACE = 1,
    MOVE_WRITE_THROUGH = 8,
    COMMAND_LIMIT = 32768
};

typedef struct {
    wchar_t *text;
    size_t length;
} Command;

static int append(Command *command, const wchar_t *text) {
    while (*text) {
        if (command->length >= COMMAND_LIMIT - 1)
            return 0;
        command->text[command->length++] = *text++;
    }
    command->text[command->length] = 0;
    return 1;
}

static int quoted(Command *command, const wchar_t *text) {
    /* These arguments are file names, an IPv4 address, or a version number.
       Windows file names cannot contain quotes. No argument ends in a slash. */
    for (const wchar_t *character = text; *character; ++character)
        if (*character == L'"')
            return 0;
    return append(command, L"\"") && append(command, text) && append(command, L"\"");
}

static int launch(const wchar_t *target, const wchar_t *marker,
                  const wchar_t *address, const wchar_t *version, ProcessInfo *child) {
    Handle heap = WIN(GetProcessHeap)();
    Command command = {WIN(HeapAlloc)(heap, 0, COMMAND_LIMIT * sizeof(wchar_t)), 0};
    if (!command.text)
        return 0;
    int formed = quoted(&command, target);
    if (marker) {
        formed = formed && append(&command, L" -- --resume-launcher-update ") && quoted(&command, marker) &&
            append(&command, L" ") && quoted(&command, address) &&
            append(&command, L" ") && quoted(&command, version);
    } else {
        formed = formed && append(&command, L" -- --launcher-update-failed");
    }
    StartupInfo startup = {sizeof(startup), {0}};
    int launched = formed && WIN(CreateProcessW)(target, command.text, NULL, NULL, 0, 0, NULL, NULL, &startup, child);
    WIN(HeapFree)(heap, 0, command.text);
    if (launched)
        WIN(CloseHandle)(child->thread);
    return launched;
}

static int exists(const wchar_t *path) {
    return WIN(GetFileAttributesW)(path) != UINT32_MAX;
}

static int restore(const wchar_t *target, const wchar_t *backup) {
    for (int attempt = 0; attempt < 20; ++attempt) {
        if (WIN(MoveFileExW)(backup, target, MOVE_REPLACE | MOVE_WRITE_THROUGH))
            return 1;
        WIN(Sleep)(200);
    }
    return 0;
}

static int replace_when_closed(const wchar_t *target, const wchar_t *pending, const wchar_t *backup) {
    for (int attempt = 0; attempt < 20; ++attempt) {
        if (WIN(ReplaceFileW)(target, pending, backup, 0, NULL, NULL))
            return 1;
        if (exists(backup))
            return 0;
        WIN(Sleep)(200);
    }
    return 0;
}

static uint32_t parse_pid(const wchar_t *text) {
    uint32_t value = 0;
    for (; *text; ++text) {
        if (*text < L'0' || *text > L'9' || value > (UINT32_MAX - 9) / 10)
            return 0;
        value = value * 10 + (*text - L'0');
    }
    return value;
}

static int update(uint32_t parent, const wchar_t *target, const wchar_t *pending,
                  const wchar_t *backup, const wchar_t *marker,
                  const wchar_t *address, const wchar_t *version) {
    Handle old_process = WIN(OpenProcess)(SYNCHRONIZE, 0, parent);
    if (old_process) {
        uint32_t waited = WIN(WaitForSingleObject)(old_process, 15000);
        WIN(CloseHandle)(old_process);
        if (waited != WAIT_COMPLETE) {
            WIN(DeleteFileW)(pending);
            WIN(MessageBoxW)(NULL, L"The launcher stayed open. Close it and open it again to retry.",
                L"Stomp & Scurry update", 0x30);
            return 1;
        }
    }
    WIN(DeleteFileW)(marker);
    ProcessInfo child;
    if (replace_when_closed(target, pending, backup) && launch(target, marker, address, version, &child)) {
        int ready = 0;
        for (int attempt = 0; attempt < 180; ++attempt) {
            if (WIN(WaitForSingleObject)(child.process, 100) != WAIT_PENDING)
                break;
            if (exists(marker)) {
                ready = 1;
                break;
            }
        }
        if (!ready) {
            WIN(TerminateProcess)(child.process, 1);
            WIN(WaitForSingleObject)(child.process, 5000);
        }
        WIN(CloseHandle)(child.process);
        WIN(DeleteFileW)(marker);
        if (ready) {
            WIN(DeleteFileW)(backup);
            return 0;
        }
    }

    if (exists(backup) && !restore(target, backup)) {
        WIN(MessageBoxW)(NULL, backup, L"Could not restore the launcher. Your previous copy is here", 0x10);
        return 1;
    }
    WIN(DeleteFileW)(pending);
    if (launch(target, NULL, NULL, NULL, &child)) {
        WIN(CloseHandle)(child.process);
    } else {
        WIN(MessageBoxW)(NULL, L"Couldn't restart the launcher. Open it again to retry.",
            L"Stomp & Scurry update", 0x30);
    }
    return 1;
}

void restart_entry(void) {
    int count = 0;
    wchar_t **arguments = WIN(CommandLineToArgvW)(WIN(GetCommandLineW)(), &count);
    uint32_t parent = arguments && count == 8 ? parse_pid(arguments[1]) : 0;
    if (!parent)
        WIN(ExitProcess)(2);
    else
        WIN(ExitProcess)(update(parent, arguments[2], arguments[3], arguments[4],
            arguments[5], arguments[6], arguments[7]));
}
