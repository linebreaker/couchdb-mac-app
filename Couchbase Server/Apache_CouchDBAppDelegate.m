/*
 *  Author: Jan Lehnardt <jan@apache.org>
 *  This is Apache 2.0 licensed free software
 */
#import "Apache_CouchDBAppDelegate.h"
#import "iniparser.h"

@implementation CouchDBAppDelegate

-(void)applicationWillTerminate:(NSNotification *)notification
{
    NSLog(@"in applicationWillTerminate");
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    NSLog(@"in windowWillClose");
//    [self stop];
}

-(void)applicationWillFinishLaunching:(NSNotification *)notification
{
}

- (IBAction)showAboutPanel:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [[NSApplication sharedApplication] orderFrontStandardAboutPanel:sender];
}

-(void)logMessage:(NSString*)msg {
    const char *str = [msg cStringUsingEncoding:NSUTF8StringEncoding];
    if (str) {
        fwrite(str, strlen(str), 1, logFile);
    }
}

-(void)flushLog {
    fflush(logFile);
}

- (NSString *)finalConfigPath {
    NSString *confFile = nil;
    FSRef foundRef;
    OSErr err = FSFindFolder(kUserDomain, kPreferencesFolderType, kDontCreateFolder, &foundRef);
    if (err == noErr) {
        unsigned char path[PATH_MAX];
        OSStatus validPath = FSRefMakePath(&foundRef, path, sizeof(path));
        if (validPath == noErr) {
            confFile = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:(const char *)path
                                                                                   length:(NSUInteger)strlen((char*)path)];
        }
    }
    confFile = [confFile stringByAppendingPathComponent:@"couchdb-server.ini"];
    return confFile;
}

- (NSString *)logFilePath:(NSString*)logName {
    NSString *logDir = nil;
    FSRef foundRef;
    OSErr err = FSFindFolder(kUserDomain, kLogsFolderType, kDontCreateFolder, &foundRef);
    if (err == noErr) {
        unsigned char path[PATH_MAX];
        OSStatus validPath = FSRefMakePath(&foundRef, path, sizeof(path));
        if (validPath == noErr) {
            logDir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:(const char *)path
                                                                                 length:(NSUInteger)strlen((char*)path)];
        }
    }
  logDir = [logDir stringByAppendingPathComponent:logName];
    return logDir;
}

-(void)awakeFromNib
{
    logPath = [[self logFilePath:@"couchdb.log"] retain];
    const char *logPathC = [logPath cStringUsingEncoding:NSUTF8StringEncoding];

    NSString *oldLogFileString = [self logFilePath:@"couchdb.log.old"];
    const char *oldLogPath = [oldLogFileString cStringUsingEncoding:NSUTF8StringEncoding];
    rename(logPathC, oldLogPath); // This will fail the first time.

    // Now our logs go to a private file.
    logFile = fopen(logPathC, "w");

    [NSTimer scheduledTimerWithTimeInterval:1.0
                                    target:self selector:@selector(flushLog)
                                    userInfo:nil
                                    repeats:YES];

    [[NSUserDefaults standardUserDefaults]
     registerDefaults: [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithBool:YES], @"browseAtStart",
                        [NSNumber numberWithBool:YES], @"runImport", nil, nil]];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Make sure we have a unique identifier for this installation.
    if ([defaults valueForKey:@"uniqueness"] == nil) {
        CFUUIDRef uuidObj = CFUUIDCreate(nil);
        NSString *uuidString = (NSString*)CFUUIDCreateString(nil, uuidObj);
        CFRelease(uuidObj);

        [defaults setValue:uuidString forKey:@"uniqueness"];
        [defaults synchronize];

        [uuidString release];
    }

    statusBar=[[NSStatusBar systemStatusBar] statusItemWithLength: 26.0];
    NSImage *statusIcon = [NSImage imageNamed:@"CouchDb-Status-bw.png"];
    [statusIcon setTemplate:YES];
    [statusBar setImage: statusIcon];
    [statusBar setMenu: statusMenu];
    [statusBar setEnabled:YES];
    [statusBar setHighlightMode:YES];
    [statusBar retain];

    // Fix up the masks for all the alt items.
    for (int i = 0; i < [statusMenu numberOfItems]; ++i) {
        NSMenuItem *itm = [statusMenu itemAtIndex:i];
        if ([itm isAlternate]) {
            [itm setKeyEquivalentModifierMask:NSAlternateKeyMask];
        }
    }

    [launchBrowserItem setState:([defaults boolForKey:@"browseAtStart"] ? NSOnState : NSOffState)];
    [self updateAddItemButtonState];

  [self launchCouchDB];
}

-(IBAction)start:(id)sender
{
    if([task isRunning]) {
        [self stop:self];
        return;
    }

    [self launchCouchDB];
}

-(IBAction)stop:(id)sender
{
    NSLog(@"in stop");
    NSLog(@"calling [task terminate]");
    [task terminate];
    [[NSApplication sharedApplication] terminate:self];
}

/* found at http://www.cocoadev.com/index.pl?ApplicationSupportFolder */
- (NSString *)applicationSupportFolder:(NSString*)appName {
    NSString *applicationSupportFolder = nil;
    FSRef foundRef;
    OSErr err = FSFindFolder(kUserDomain, kApplicationSupportFolderType, kDontCreateFolder, &foundRef);
    if (err == noErr) {
        unsigned char path[PATH_MAX];
        OSStatus validPath = FSRefMakePath(&foundRef, path, sizeof(path));
        if (validPath == noErr) {
            applicationSupportFolder = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:(const char *)path
                                                                                                   length:(NSUInteger)strlen((char*)path)];
        }
    }
  applicationSupportFolder = [applicationSupportFolder stringByAppendingPathComponent:appName];
    return applicationSupportFolder;
}

- (NSString *)applicationSupportFolder {
    return [self applicationSupportFolder:@"CouchDB"];
}

-(void)setInitParams
{
  // determine data dir
  NSString *dataDir = [self applicationSupportFolder];

    // database and views dir
    NSString *dbDir = [dataDir stringByAppendingString:@"/var/lib/couchdb"];

  // create if it doesn't exist
  if(![[NSFileManager defaultManager] fileExistsAtPath:dataDir]) {
    [[NSFileManager defaultManager] createDirectoryAtPath:dataDir withIntermediateDirectories:YES attributes:nil error:NULL];
  }

    // config dir
    NSString *confDir = [dataDir stringByAppendingString:@"/etc/couchdb"];

  // create if it doesn't exist
  if(![[NSFileManager defaultManager] fileExistsAtPath:confDir]) {
    [[NSFileManager defaultManager] createDirectoryAtPath:confDir withIntermediateDirectories:YES attributes:nil error:NULL];

        // remove old file, if any
        [[NSFileManager defaultManager] removeItemAtPath: [self finalConfigPath] error: NULL];

        // create sym link to local.ini
        NSString *localIni = [confDir stringByAppendingString:@"/local.ini"];
        if ([[NSFileManager defaultManager] createFileAtPath:localIni contents:nil attributes:nil]) {
            [[NSFileManager defaultManager] createSymbolicLinkAtPath: [self finalConfigPath] withDestinationPath: localIni error: NULL];
        }
  }

    dictionary* iniDict = iniparser_load([[self finalConfigPath] UTF8String]);
    if (iniDict == NULL) {
        iniDict = dictionary_new(0);
        assert(iniDict);
    }

    dictionary_set(iniDict, "couchdb", NULL);
    if (iniparser_getstring(iniDict, "couchdb:database_dir", NULL) == NULL) {
        dictionary_set(iniDict, "couchdb:database_dir", [dbDir UTF8String]);
    }
    if (iniparser_getstring(iniDict, "couchdb:view_index_dir", NULL) == NULL) {
        dictionary_set(iniDict, "couchdb:view_index_dir", [dbDir UTF8String]);
    }

    // uri dir
    NSString *runDir = [dataDir stringByAppendingString:@"/var/run/couchdb"];

  // create if it doesn't exist
  if(![[NSFileManager defaultManager] fileExistsAtPath:runDir]) {
    [[NSFileManager defaultManager] createDirectoryAtPath:runDir withIntermediateDirectories:YES attributes:nil error:NULL];
  }
    NSString *uriFile = [runDir stringByAppendingString:@"/couch.uri"];
    dictionary_set(iniDict, "couchdb:uri_file", [uriFile UTF8String]);

    dictionary_set(iniDict, "query_servers", NULL);
    dictionary_set(iniDict, "query_servers:javascript", "bin/couchjs share/couchdb/server/main.js");
    dictionary_set(iniDict, "query_servers:coffeescript", "bin/couchjs share/couchdb/server/main-coffee.js");

    // full log file
    NSString *logDir = [dataDir stringByAppendingString:@"/var/log/couchdb"];

    // create if it doesn't exist
  if(![[NSFileManager defaultManager] fileExistsAtPath:logDir]) {
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:NULL];
  }

    NSString *fullLogFile = [logDir stringByAppendingString:@"/couch.log"];
    dictionary_set(iniDict, "log", NULL);
    dictionary_set(iniDict, "log:file", [fullLogFile UTF8String]);

    dictionary_set(iniDict, "product", NULL);
    NSString *vstr = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    //dictionary_set(iniDict, "product:title", [vstr UTF8String]);

    // additional overrides for 1.3.0 pre
    NSString *utilDriverDir = [@"lib/couchdb/erlang/lib/couch-" stringByAppendingString:vstr];
    dictionary_set(iniDict, "couchdb:util_driver_dir", [[utilDriverDir stringByAppendingString:@"/priv/lib"] UTF8String]);
    dictionary_set(iniDict, "couchdb:index_dir", [dbDir UTF8String]);
    dictionary_set(iniDict, "httpd_global_handlers", NULL);
    dictionary_set(iniDict, "httpd_global_handlers:_utils", "{couch_httpd_misc_handlers, handle_utils_dir_req, \"share/couchdb/www\"}");
    dictionary_set(iniDict, "httpd_global_handlers:favicon.ico", "{couch_httpd_misc_handlers, handle_favicon_req, \"share/couchdb/www\"}");

    FILE *f = fopen([[self finalConfigPath] UTF8String], "w");
    if (f) {
        iniparser_dump_ini(iniDict, f);
        fclose(f);
    } else {
        NSLog(@"Can't write to config file:  %@:  %s\n", [self finalConfigPath], strerror(errno));
    }

    iniparser_freedict(iniDict);
}

-(void)launchCouchDB
{
  [self setInitParams];

  in = [[NSPipe alloc] init];
  out = [[NSPipe alloc] init];
  task = [[NSTask alloc] init];

  startTime = time(NULL);

  NSMutableString *launchPath = [[NSMutableString alloc] init];
  [launchPath appendString:[[NSBundle mainBundle] resourcePath]];
  [launchPath appendString:@"/couchdbx-core"];
  [task setCurrentDirectoryPath:launchPath];

  NSDictionary *env = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"./bin:/bin:/usr/bin", @"PATH",
                         NSHomeDirectory(), @"HOME",
                         nil, nil];
  [task setEnvironment:env];

  [launchPath appendString:@"/bin/couchdb"];
  [self logMessage:[NSString stringWithFormat:@"Launching '%@'\n", launchPath]];
  [task setLaunchPath:launchPath];
  [task setStandardInput:in];
  [task setStandardOutput:out];

  NSFileHandle *fh = [out fileHandleForReading];
  NSNotificationCenter *nc;
  nc = [NSNotificationCenter defaultCenter];

  [nc addObserver:self
           selector:@selector(taskTerminated:)
               name:NSTaskDidTerminateNotification
             object:task];

  // see if there are useful nstask notifications, if not:
  // send request to 127.0.0.1:5984 every second until it succeeds
  // then maybe open futon

  [task launch];
  [fh readInBackgroundAndNotify];
  [self waitForAPI];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults boolForKey:@"browseAtStart"]) {
      [self openFuton];
  }
}

-(void) waitForAPI
{
  int times = 10;
  while (times--) {
    // Send a synchronous request
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:5984/_up"]];
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:urlRequest
                          returningResponse:&response
                                      error:&error];
    // if code == 200, return
    // http://stackoverflow.com/questions/25431042/nsurlresponse-how-to-get-status-code#25431043
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;
    NSLog(@"response status code: %ld", (long)[httpResponse statusCode]);
    NSLog(@"%@", data);
    if (200 == [httpResponse statusCode]) {
      return;
    }
    [NSThread sleepForTimeInterval:1.0f]; // snooze 1s
  }
  [self logMessage: @"Can’t reach http://127.0.0.1:5984/ after 10 seconds, giving up."];
  [self logMessage: @"Please check ~/Library/Logs/CouchDB2.log for details"];
}

-(void)taskTerminated:(NSNotification *)note
{
    [self cleanup];
    [self logMessage: [NSString stringWithFormat:@"Terminated with status %d\n",
                       [[note object] terminationStatus]]];

    time_t now = time(NULL);
    if (now - startTime < MIN_LIFETIME) {
        NSInteger b = NSRunAlertPanel(@"Problem Running CouchDB",
                                      @"CouchDB Server doesn't seem to be operating properly.  "
                                      @"Check Console logs for more details.", @"Retry", @"Quit", nil);
        if (b == NSAlertAlternateReturn) {
            [NSApp terminate:self];
        }
    }

    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(launchCouchDB) userInfo:nil repeats:NO];
}

-(void)cleanup
{
    [task release];
    task = nil;

    [in release];
    in = nil;
    [out release];
    out = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)openFuton
{
  NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
  NSString *homePage = [info objectForKey:@"HomePage"];
    NSURL *url=[NSURL URLWithString:homePage];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

-(IBAction)browse:(id)sender
{
  [self openFuton];
}

-(IBAction)setLaunchPref:(id)sender {

    NSCellStateValue stateVal = [sender state];
    stateVal = (stateVal == NSOnState) ? NSOffState : NSOnState;

    NSLog(@"Setting launch pref to %s", stateVal == NSOnState ? "on" : "off");

    [[NSUserDefaults standardUserDefaults]
     setBool:(stateVal == NSOnState)
     forKey:@"browseAtStart"];

    [launchBrowserItem setState:([[NSUserDefaults standardUserDefaults]
                                  boolForKey:@"browseAtStart"] ? NSOnState : NSOffState)];

    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(void) updateAddItemButtonState {
    [launchAtStartupItem setState:[loginItems inLoginItems] ? NSOnState : NSOffState];
}

-(IBAction)changeLoginItems:(id)sender {
    if([sender state] == NSOffState) {
        [loginItems addToLoginItems:self];
    } else {
        [loginItems removeLoginItem:self];
    }
    [self updateAddItemButtonState];
}

- (IBAction)showImportWindow:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"runImport"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self logMessage:@"Starting import"];
    [NSApp activateIgnoringOtherApps:YES];

//    ImportController *controller = [[ImportController alloc]
//                                    initWithWindowNibName:@"Importer"];

//    [controller setPaths:[self applicationSupportFolder]
//                    from:[self applicationSupportFolder:@"CouchDBX"]];
//    [controller loadWindow];

//    if (sender != nil && ![controller hasImportableDBs]) {
//        NSRunAlertPanel(@"No Importable Databases",
//                        @"No databases can be imported from CouchDBX.", nil, nil, nil);
//    }
}

-(IBAction)showTechSupport:(id)sender {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
  NSString *homePage = [info objectForKey:@"SupportPage"];
    NSURL *url=[NSURL URLWithString:homePage];
    [[NSWorkspace sharedWorkspace] openURL:url];

}

-(IBAction)showLogs:(id)sender {
    FSRef ref;

    if (FSPathMakeRef((const UInt8 *)[logPath cStringUsingEncoding:NSUTF8StringEncoding],
                      &ref, NULL) != noErr) {
        NSRunAlertPanel(@"Cannot Find Logfile",
                        @"I've been looking for logs in all the wrong places.", nil, nil, nil);
        return;
    }

    LSLaunchFSRefSpec params = {NULL, 1, &ref, NULL, kLSLaunchDefaults, NULL};

    if (LSOpenFromRefSpec(&params, NULL) != noErr) {
        NSRunAlertPanel(@"Cannot View Logfile",
                        @"Error launching log viewer.", nil, nil, nil);
    }
}

@end
