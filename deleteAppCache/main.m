//
//  main.m
//  deleteAppCache
//
//  Created by itisdev on 5/28/14.
//  Copyright (c) 2014 Trend Micro. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <CoreFoundation/CoreFoundation.h>
#import "MobileDevice.h"
#import "main.h"
//#include "listener.h"

void read_dir(service_conn_t afcFd, afc_connection* afc_conn_p, const char* dir)
{
    char *dir_ent;
    
    afc_connection afc_conn;
    if (!afc_conn_p) {
        afc_conn_p = &afc_conn;
        AFCConnectionOpen(afcFd, 0, &afc_conn_p);
    }
    
    printf("%s\n", dir);
    
    afc_dictionary afc_dict;
    afc_dictionary* afc_dict_p = &afc_dict;
    //afc_dictionary * afc_dict_p = malloc(sizeof(afc_dictionary));
    AFCFileInfoOpen(afc_conn_p, dir, &afc_dict_p);
    
    afc_directory afc_dir;
    afc_directory* afc_dir_p = &afc_dir;
    afc_error_t err = AFCDirectoryOpen(afc_conn_p, dir, &afc_dir_p);
    
    if (err != 0)
    {
        // Couldn't open dir - was probably a file
        return;
    }
    
    while(true) {
        AFCDirectoryRead(afc_conn_p, afc_dir_p, &dir_ent);
        
        if (!dir_ent)
            break;
        
        if (strcmp(dir_ent, ".") == 0 || strcmp(dir_ent, "..") == 0)
            continue;
        
        char* dir_joined = malloc(strlen(dir) + strlen(dir_ent) + 2);
        strcpy(dir_joined, dir);
        if (dir_joined[strlen(dir)-1] != '/')
            strcat(dir_joined, "/");
        strcat(dir_joined, dir_ent);
        read_dir(afcFd, afc_conn_p, dir_joined);
        printf("%s\n", dir_joined);

        
        err = AFCRemovePath(afc_conn_p, dir_joined);
        if (err != 0) {
            printf("%d\n",err);
        }
        free(dir_joined);
    }
    
    AFCDirectoryClose(afc_conn_p, afc_dir_p);
}
void list_files(struct am_device * device, char * bundle_id)
{
    
    service_conn_t houseFd;
    //bundle_id = "teladi.game.flappy2048";
    
    CFStringRef cf_bundle_id = CFStringCreateWithCString(NULL, bundle_id, kCFStringEncodingASCII);
    mach_error_t service_err = 0;
    service_err=AMDeviceStartHouseArrestService(device, cf_bundle_id, 0, &houseFd, 0);
    if (service_err != 0)
    {
        //PRINT("Unable to find bundle with id: %s\n", bundle_id);
        printf("%d\n",service_err);
        CFRelease(cf_bundle_id);
        //exit(1);
        return;
    }
    
    afc_connection afc_conn;
    afc_connection* afc_conn_p = &afc_conn;
    //afc_connection * afc_conn_p =  malloc(sizeof(afc_connection));
    afc_error_t err = AFCConnectionOpen(houseFd, 0, &afc_conn_p);
    if (err != MDERR_OK) {
        CFRelease(cf_bundle_id);
        return;
    }
    
    read_dir(houseFd, afc_conn_p, "/Library/Caches");
    
    AFCConnectionClose(afc_conn_p);
    CFRelease(cf_bundle_id);
}

kern_return_t test_apple_AMDeviceLookupApplications(struct am_device *apple, CFTypeRef *value) {
	CFDictionaryRef apple_response = NULL;
	kern_return_t apple_return = kAMDUndefinedError;
	kern_return_t result = AMDeviceConnect(apple);
	if (SDM_MD_CallSuccessful(result)) {
		result = AMDeviceStartSession(apple);
		if (SDM_MD_CallSuccessful(result)) {
            
			//CFArrayRef lookupValues = SDMMD_ApplicationLookupDictionary();
			//CFMutableDictionaryRef optionsDict = SDMMD_create_dict();
			//CFDictionarySetValue(optionsDict, CFSTR("ReturnAttributes"), lookupValues);
            CFDictionaryRef optionsDict = NULL;
			apple_return = AMDeviceLookupApplications(apple, optionsDict, &apple_response);
			if (apple_return != kAMDSuccess) {
				printf("\t\tAMDeviceLookupApplications: %08x %s\n",apple_return,SDMMD_AMDErrorString(apple_return));
			}
			else {
				*value = apple_response;
			}
			
			AMDeviceStopSession(apple);
		}
		AMDeviceDisconnect(apple);
	}
	return apple_return;
}


kern_return_t delete_app_cache(struct am_device * apple, char * bundle_id){
    kern_return_t apple_return = kAMDUndefinedError;
	kern_return_t result = AMDeviceConnect(apple);
	if (SDM_MD_CallSuccessful(result)) {
		result = AMDeviceStartSession(apple);
		if (SDM_MD_CallSuccessful(result)) {
            
            list_files(apple, bundle_id);
            AMDeviceStopSession(apple);
        }
        AMDeviceDisconnect(apple);
    }
    return apple_return;
}

#pragma mark - apple
int timeout = 0;
bool found_device = false;
typedef struct am_device * AMDeviceRef;
char *device_id = NULL;

void timeout_callback(CFRunLoopTimerRef timer, void *info) {
    if (!found_device) {
        printf("Timed out waiting for device.\n");
        exit(1);
    }
}
void handle_device(AMDeviceRef device) {
    if (found_device) return; // handle one device only
    
    CFStringRef found_device_id = AMDeviceCopyDeviceIdentifier(device);
    
    if (device_id != NULL) {
        if(strcmp(device_id, CFStringGetCStringPtr(found_device_id, CFStringGetSystemEncoding())) == 0) {
            found_device = true;
        } else {
            return;
        }
    } else {
        found_device = true;
    }
    
    CFRetain(device); // don't know if this is necessary?
    
    printf("[  0%%] Found device (%s), beginning\n", CFStringGetCStringPtr(found_device_id, CFStringGetSystemEncoding()));
    
    CFTypeRef apple_response = NULL;
    test_apple_AMDeviceLookupApplications(device, &apple_response);
    NSDictionary * dic_apps_info = (__bridge NSDictionary *)(apple_response);
    NSArray * arr_apps_bundle = [dic_apps_info allKeys];
    for (NSString * str_app_bundle in arr_apps_bundle) {
        char * bundle_id = [str_app_bundle cStringUsingEncoding:NSASCIIStringEncoding];
        delete_app_cache(device, bundle_id);
        
    }
    
    CFRelease(found_device_id);
    exit(0);
    
}
void device_callback(struct am_device_notification_callback_info *info, void *arg) {
    switch (info->msg) {
        case ADNCI_MSG_CONNECTED:
            handle_device(info->dev);
        default:
            break;
    }
}
int main(int argc, const char * argv[])
{

    @autoreleasepool {
        
        // insert code here...
        if (timeout > 0)
        {
            CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + timeout, 0, 0, 0, timeout_callback, NULL);
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
            printf("[....] Waiting up to %d seconds for iOS device to be connected\n", timeout);
        }
        else
        {
            printf("[....] Waiting for iOS device to be connected\n");
        }
        
        struct am_device_notification *notify;
        AMDeviceNotificationSubscribe(&device_callback, 0, 0, NULL, &notify);
        CFRunLoopRun();
        
    }
    return 0;
}

