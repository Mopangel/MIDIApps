#import "SSEDetailsWindowController.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <SnoizeMIDI/SnoizeMIDI.h>

#import "SSELibrary.h"
#import "SSELibraryEntry.h"


@interface SSEDetailsWindowController (Private)

- (void)synchronizeMessageDataDisplay;
- (void)synchronizeTitle;

- (void)entryWillBeRemoved:(NSNotification *)notification;
- (void)entryNameDidChange:(NSNotification *)notification;

- (NSString *)formatSysExData:(NSData *)data;

@end


@implementation SSEDetailsWindowController

static NSMutableArray *controllers = nil;

+ (SSEDetailsWindowController *)detailsWindowControllerWithEntry:(SSELibraryEntry *)inEntry;
{
    unsigned int controllerIndex;
    SSEDetailsWindowController *controller;

    if (!controllers) {
        controllers = [[NSMutableArray alloc] init];
    }

    controllerIndex = [controllers count];
    while (controllerIndex--) {
        controller = [controllers objectAtIndex:controllerIndex];
        if ([controller entry] == inEntry)
            return controller;
    }

    controller = [[SSEDetailsWindowController alloc] initWithEntry:inEntry];
    [controllers addObject:controller];
    [controller release];

    return controller;
}

- (id)initWithEntry:(SSELibraryEntry *)inEntry;
{
    if (!(self = [super initWithWindowNibName:@"Details"]))
        return nil;

    [self setShouldCascadeWindows:YES];

    entry = [inEntry retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(entryWillBeRemoved:) name:SSELibraryEntryWillBeRemovedNotification object:entry];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(entryNameDidChange:) name:SSELibraryEntryNameDidChangeNotification object:entry];
    
    cachedMessages = [[NSArray alloc] initWithArray:[entry messages]];

    return self;
}

- (id)initWithWindowNibName:(NSString *)windowNibName;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [entry release];
    entry = nil;
    [cachedMessages release];
    cachedMessages = nil;
        
    [super dealloc];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    [self synchronizeTitle];
    
    [messagesTableView reloadData];
    if ([cachedMessages count] > 0)
        [messagesTableView selectRow:0 byExtendingSelection:NO];

    [self synchronizeMessageDataDisplay];
}

- (SSELibraryEntry *)entry;
{
    return entry;
}

//
// Actions
//

- (IBAction)selectAll:(id)sender;
{
    // Forward to the text view, even if it isn't the first responder
    [textView selectAll:sender];
}

@end


@implementation SSEDetailsWindowController (NotificationsDelegatesDataSources)

//
// NSWindow delegate
//

- (void)windowWillClose:(NSNotification *)notification;
{
    [[self retain] autorelease];
    [controllers removeObjectIdenticalTo:self];
}

//
// NSTableView data source
//

- (int)numberOfRowsInTableView:(NSTableView *)tableView;
{
    return [cachedMessages count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row;
{
    NSString *identifier;
    SMSystemExclusiveMessage *message;

    identifier = [tableColumn identifier];
    message = [cachedMessages objectAtIndex:row];

    if ([identifier isEqualToString:@"index"]) {
        return [NSNumber numberWithInt:row + 1];
    } else if ([identifier isEqualToString:@"manufacturer"]) {
        return [message manufacturerName];
    } else if ([identifier isEqualToString:@"sizeDecimal"]) {
        return [SMMessage formatLength:[message receivedDataWithStartByteLength] usingOption:SMDataFormatDecimal];
    } else if ([identifier isEqualToString:@"sizeHex"]) {
        return [SMMessage formatLength:[message receivedDataWithStartByteLength] usingOption:SMDataFormatHexadecimal];
    } else if ([identifier isEqualToString:@"sizeAbbreviated"]) {
        return [NSString abbreviatedStringForBytes:[message receivedDataWithStartByteLength]];
    } else {
        return nil;
    }
}

//
// NSTableView delegate
//

- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
    [self synchronizeMessageDataDisplay];
}

//
// NSSplitView delegate
//

- (float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedMax ofSubviewAt:(int)offset;
{
    return MIN(proposedMax, NSHeight([sender frame]) - 32);    
}

- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset;
{
    return MAX(proposedMin, 32);
}

@end


@implementation SSEDetailsWindowController (Private)

- (void)synchronizeMessageDataDisplay;
{
    int selectedRow;
    NSString *formattedData;

    selectedRow = [messagesTableView selectedRow];
    if (selectedRow >= 0) {
        formattedData = [self formatSysExData:[[cachedMessages objectAtIndex:selectedRow] receivedDataWithStartByte]];
    } else {
        formattedData = @"";
    }

    [textView setString:formattedData];
}

- (void)synchronizeTitle;
{
    [[self window] setTitle:[entry name]];
    [[self window] setRepresentedFilename:[entry path]];
}

- (void)entryWillBeRemoved:(NSNotification *)notification;
{
    [self close];
}

- (void)entryNameDidChange:(NSNotification *)notification;
{
    [self synchronizeTitle];
}

- (NSString *)formatSysExData:(NSData *)data;
{
    unsigned int dataLength;
    const unsigned char *bytes;
    NSMutableString *formattedString;
    unsigned int dataIndex;
    int lengthDigitCount;
    unsigned int scratchLength;

    dataLength = [data length];
    if (dataLength == 0)
        return @"";

    bytes = [data bytes];

    // Figure out how many bytes dataLength takes to represent
    lengthDigitCount = 0;
    scratchLength = dataLength;
    while (scratchLength > 0) {
        lengthDigitCount += 2;
        scratchLength >>= 8;
    }

    formattedString = [NSMutableString string];
    for (dataIndex = 0; dataIndex < dataLength; dataIndex += 16) {
        static const char hexchars[] = "0123456789ABCDEF";
        char lineBuffer[100];
        char *p;
        unsigned int index;
        NSString *lineString;

        // This C stuff may be a little ugly but it is a hell of a lot faster than doing it with NSStrings...

        p = lineBuffer;
        p += sprintf(p, "%.*X", lengthDigitCount, dataIndex);
        
        for (index = dataIndex; index < dataIndex+16; index++) {
            *p++ = ' ';
            if (index % 8 == 0)
                *p++ = ' ';

            if (index < dataLength) {
                unsigned char byte;

                byte = bytes[index];
                *p++ = hexchars[(byte & 0xF0) >> 4];
                *p++ = hexchars[byte & 0x0F];
            } else {
                *p++ = ' ';
                *p++ = ' ';                                
            }
        }

        *p++ = ' ';
        *p++ = ' ';
        *p++ = '|';

        for (index = dataIndex; index < dataIndex+16 && index < dataLength; index++) {
            unsigned char byte;

            byte = bytes[index];
            *p++ = (isprint(byte) ? byte : ' ');
        }
        
        *p++ = '|';
        *p++ = '\n';
        *p++ = 0;

        lineString = [[NSString alloc] initWithCString:lineBuffer];
        [formattedString appendString:lineString];
        [lineString release];
    }

    return formattedString;
}

@end