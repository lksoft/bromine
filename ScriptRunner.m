//
//  ScriptRunner.m
//  SelfTesting
//
//  Created by Matt Gallagher on 9/10/08.
//  Copyright 2008 Matt Gallagher. All rights reserved.
//

#ifdef BROMINE_ENABLED

#import "ScriptRunner.h"
#import "XMLDescription.h"
#import "XPathQuery.h"
#import "TouchSynthesis.h"
#import "NSObject+ClassName.h"

const float SCRIPT_RUNNER_INTER_COMMAND_DELAY = 0.0;
const float MAX_WAIT_ATTEMPTS = 60;
const float WAIT_ATTEMPT_DELAY = 0.25;
const float BACKBUTTON_WAIT_DELAY = 0.75;

@implementation ScriptRunner

@synthesize currentScriptName;



//
// init
//
// Init method for the object.
//
- (id)init {
	self = [super init];
	if (self != nil)
	{
		//	Get all bromine scripts
		scriptList = [[[NSBundle mainBundle] pathsForResourcesOfType:@"brscript" inDirectory:nil] mutableCopy];

		//	First assert that there are some tests to run
		NSAssert((scriptList != nil) && ([scriptList count] > 0), @"\n\n****\nNo Bromine Scripts were provided for the run\n****\n\n");
		NSLog(@"\n\n****\nFound %d Bromine Scripts to Run\n****\n\n", [scriptList count]);
		
		//	Retain ourselves to ensure that we don't go away
		[self retain];
		[self performSelector:@selector(runScript) withObject:nil afterDelay:1.0];
		
	}
	return self;
}

//
// dealloc
//
// Releases instance memory.
//
- (void)dealloc {
	[scriptCommands release];
	self.currentScriptName = nil;

	[super dealloc];
	[scriptList release];
}

//
// performTouchInView:
//
// Synthesize a touch begin/end in the center of the specified view. Since there
// is no API to do this, it's a dirty hack of a job.
//
- (void)performTouchInView:(UIView *)view
{
	UITouch *touch = [[UITouch alloc] initInView:view];
	UIEvent *event = [[UIEvent alloc] initWithTouch:touch];
	NSSet *touches = [[NSMutableSet alloc] initWithObjects:&touch count:1];
	
	[touch.view touchesBegan:touches withEvent:event];
	
	[touch setPhase:UITouchPhaseEnded];
	
	[touch.view touchesEnded:touches withEvent:event];
	
	[event release];
	[touches release];
	[touch release];
}

//
// highlighView
//
// shows a yellow rect over the provided view
//
- (void)highlightView:(UIView *)view {
	UIView *highlightView = [[UIView alloc] init];
	CGRect frame = view.frame;
	frame.origin.x = 0;
	frame.origin.y = 0;
	highlightView.frame = frame;
	highlightView.backgroundColor = [UIColor yellowColor];
	highlightView.alpha = 0.5;
	[view addSubview:highlightView];
	
	[UIView beginAnimations:@"highlight" context:nil]; 
	[UIView setAnimationDuration:1.5f];
	[UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
	highlightView.alpha = 0;
	[UIView commitAnimations];
	[highlightView release];
}

//
// viewsForXPath:
//
// Generates an XML document from the current view tree and runs the specified
// XPath query on the document. If the resulting nodes contain "address" values
// then these values are interrogated to determine if they are UIViews. All
// UIViews found in this way are returned in the array.
//
- (NSArray *)viewsForXPath:(NSString *)xpath
{
	//printf("XML \n%s\n\n", [[[[UIApplication sharedApplication] keyWindow] xmlDescription] cStringUsingEncoding:NSUTF8StringEncoding]);
	NSData *resultData =
	[[[UIApplication sharedApplication] xmlDescription] dataUsingEncoding: NSUTF8StringEncoding];
	
	NSArray *queryResults = PerformXMLXPathQuery(resultData, xpath);
	//printf("%s", [queryResults.description UTF8String]);
	NSMutableArray *views =
	[NSMutableArray arrayWithCapacity:[queryResults count]];
	for (NSDictionary *result in queryResults)
	{
		int i;
		int count = [[result objectForKey:@"nodeChildArray"] count];
		for (i = 0; i < count; i++)
		{
			NSDictionary *childNode = [[result objectForKey:@"nodeChildArray"] objectAtIndex:i];
			if ([[childNode objectForKey:@"nodeName"] isEqualToString:@"address"] )
			{
				UIView *view =
				(UIView *)[[childNode objectForKey:@"nodeContent"] integerValue];
				NSAssert([view isKindOfClass:[UIView class]],
						 @"XPath selected memory address did not contain a UIView");
				[views addObject:view];
				
				[self highlightView:view];
				break;
			}
		}
	}
	return views;
}

#pragma mark -
#pragma mark Available test commands

//
// outputView
//
// This command outputs the current view hierarchy, starting with the
// keyWindow, to a file or stdout.
//
// Required parameter:
//
// Optional paramter:
//	outputPath (file path to save PropertyList description of hierarchy, if omitted print to stdout)
//	viewXPath (only output views matching this XPath)
//
- (void) outputView: (NSDictionary *) command  {
	NSString *path = [command objectForKey:@"outputPath"];
		
	NSString *viewXPath = [command objectForKey:@"viewXPath"];
	
	printf("=== outputView\n    outputPath:\n        %s\n    viewXPath:\n        %s\n",
		   [path cStringUsingEncoding:NSUTF8StringEncoding],
		   [viewXPath cStringUsingEncoding:NSUTF8StringEncoding]);
	
	NSString *resultString;
	if (viewXPath)	{
		NSAssert1(0, @"not implemented yet",nil);
	}
	else {
		resultString = [[UIApplication sharedApplication] xmlDescription];
	}
	if (path == nil) {
		printf("%s", [resultString UTF8String]);
	}
	else {
		[resultString writeToFile:path atomically:YES encoding: NSUTF8StringEncoding error: nil];
	}
	
	
}

//
// waitForElement
//
// This command keeps running until the elements associated with
// the given XPath query are avaiable or gives a timeout.
//
// Required parameters:
//	viewXPath (search for views matching this XPath)
//
// Optional paramter:
//	count (wait for a specified number of elements matching viewXPath)
//
- (void) waitForElement: (NSDictionary *) command  {
	NSString *viewXPath = [command objectForKey:@"viewXPath"];
	if (viewXPath == nil)
	{
		fprintf(stderr, "### Command 'checkMatchCount' requires 'viewXPath' parameter.\n");
		exit(1);
	}
	
	NSNumber *requiredCount = [command objectForKey:@"count"];
	
	NSString *requiredCountMessage;
	if(requiredCount) {
		requiredCountMessage = [requiredCount stringValue];
	}
	else {
		requiredCountMessage = @"at least one";
	}
	
	NSNumber *numberOfAttempts = [command objectForKey:@"numberOfCalls"];
	if (numberOfAttempts == nil) {
		numberOfAttempts = [NSNumber numberWithInt:1];
		printf("=== waitForElement\n    viewXPath:\n        %s\n    count:\n        %s\n",
			   [viewXPath cStringUsingEncoding:NSUTF8StringEncoding],
			   [requiredCountMessage cStringUsingEncoding:NSUTF8StringEncoding]
			   );
		
	}
		
	printf("attempt %d\n", [numberOfAttempts intValue]);

	NSArray *views = [self viewsForXPath:viewXPath];
	
	BOOL foundElements = NO;
	if(requiredCount) {
		foundElements = [views count] == [requiredCount integerValue];
	}
	else {
		foundElements = [views count] != 0;
	}
	
	if(!foundElements) {
		
		if ([numberOfAttempts integerValue] == MAX_WAIT_ATTEMPTS) {
			if(requiredCount) {
				fprintf(
						stderr,
						"### TIMEOUT: couldn't find specified number of elements: %d\n with xpath '%s'\n found: %d\n",
						[requiredCount intValue],
						[viewXPath cStringUsingEncoding:NSUTF8StringEncoding],
						[views count]);
				
			}
			else {
				fprintf(
						stderr,
						"### TIMEOUT: couldn't find elements with xpath '%s'\n",
						[viewXPath cStringUsingEncoding:NSUTF8StringEncoding]);
			}
			exit(1);
		}
		else {
			NSMutableDictionary *newCommand = [NSMutableDictionary dictionaryWithDictionary:command];
			[newCommand setValue:[NSNumber numberWithInt:([numberOfAttempts intValue] + 1)] forKey:@"numberOfCalls"];
			[scriptCommands insertObject:newCommand atIndex:1];
			scriptRunnerInterCommandDelay = WAIT_ATTEMPT_DELAY;
		}
	}
}

//
// checkMatchCount
//
// This command verifies that the specified number of nodes matching
// the given XPath query are found.
//
// Required parameters:
//	viewXPath (search for views matching this XPath)
//	matchCount (number of nodes found must equal this number)
//
- (void) checkMatchCount: (NSDictionary *) command  {
	NSString *viewXPath = [command objectForKey:@"viewXPath"];
	if (viewXPath == nil)
	{
		fprintf(stderr, "### Command 'checkMatchCount' requires 'viewXPath' parameter.\n");
		exit(1);
	}
	
	NSNumber *matchCount = [command objectForKey:@"matchCount"];
	if (matchCount == nil)
	{
		fprintf(stderr, "### Command 'checkMatchCount' requires 'matchCount' parameter.\n");
		exit(1);
	}
	
	printf("=== checkMatchCount\n    viewXPath:\n        %s\n    matchCount: %d\n",
		   [viewXPath cStringUsingEncoding:NSUTF8StringEncoding],
		   [matchCount integerValue]);
	
	NSArray *views = [self viewsForXPath:viewXPath];
	if ([views count] != [matchCount integerValue])
	{
		fprintf(
				stderr,
				"### 'checkMatchCount' wanted a matching count of %d but encountered %d\n",
				[matchCount integerValue],
				[views count]);
		exit(1);
	}
	
}

//
// simulateTouch
//
// Performs a synthesized touch down and touch up in a single view selected
// by a given XPath query.
//
// Required parameters:
//	viewXPath (search for a view matching this XPath)
//
- (void) simulateTouch: (NSDictionary *) command  {
	NSString *viewXPath = [command objectForKey:@"viewXPath"];
	if (viewXPath == nil)
	{
		fprintf(stderr, "### Command 'simulateTouch' requires 'viewXPath' parameter.\n");
		exit(1);
	}
	
	printf("=== simulateTouch\n    viewXPath:\n        %s\n",
		   [viewXPath cStringUsingEncoding:NSUTF8StringEncoding]);
	
	NSArray *views = [self viewsForXPath:viewXPath];
	if([views count] != 1)
	{
		fprintf(
				stderr,
				"### 'viewXPath' for command 'simulateTouch' selected %d nodes, where exactly 1 is required.\n",
				[views count]);
		exit(1);
	}
	
	UIView *view = [views objectAtIndex:0];
	
	[self performTouchInView:view];
	
}

//
// touchBackButton
//
// Performs a synthesized touch down and touch up in the current back item
//
- (void)touchBackButton:(NSDictionary *)command  {
	
	// the touch won't work if the previous animation is not completed yet, so we wait a little just to make sure we are able to touch back button
	NSObject *waitedForEnoughTime = [command objectForKey:@"waitedForEnoughTime"];
	if(waitedForEnoughTime) {
		NSString *viewXPath = @"//UINavigationItemButtonView";
		
		printf("=== touchBackButton\n\n");
		
		NSArray *views = [self viewsForXPath:viewXPath];
		if([views count] == 0)
		{
			fprintf(
					stderr,
					"### command 'touchBackButton' couldn't find any back buttons\n");
			exit(1);
		}
		if([views count] > 1)
		{
			fprintf(
					stderr,
					"### command 'touchBackButton' found more then one back buttons\n");
			exit(1);
		}
		
		UIView *view = [views objectAtIndex:0];
		[self performTouchInView:view];
	}
	else {
		NSMutableDictionary *newCommand = [NSMutableDictionary dictionaryWithDictionary:command];
		[newCommand setValue:@"YES" forKey:@"waitedForEnoughTime"];
		[scriptCommands insertObject:newCommand atIndex:1];
		scriptRunnerInterCommandDelay = BACKBUTTON_WAIT_DELAY;
	}
}

//
// scrollToRow
//
// Scrolls a UITableView selected by an XPath query to the specified
// rowIndex (and optionally sectionIndex).
//
// Required parameters:
//	viewXPath (search for a table view matching this XPath)
//	rowIndex (scroll the table view to this row)
//
// Optional parameter:
//	sectionIndex (scroll the table view to the rowIndex in this section)
//

- (void) scrollToRow: (NSDictionary *) command  {
	NSString *viewXPath = [command objectForKey:@"viewXPath"];
	NSAssert(viewXPath != nil, @"Command 'scrollToRow' requires 'viewXPath' parameter");
	NSNumber *rowIndex = [command objectForKey:@"rowIndex"];
	NSAssert(viewXPath != nil, @"Command 'scrollToRow' requires 'rowIndex' parameter");
	NSNumber *sectionIndex = [command objectForKey:@"sectionIndex"];
	// sectionIndex is allowed to be nil -- will select section 0
	
	NSIndexPath *indexPath =
	[NSIndexPath
	 indexPathForRow:[rowIndex integerValue]
	 inSection:[sectionIndex integerValue]];
	
	printf("=== scrollToRow\n    viewXPath:\n        %s\n    indexPath: (section: %d, row: %d)\n",
		   [viewXPath cStringUsingEncoding:NSUTF8StringEncoding],
		   [indexPath section],
		   [indexPath row]);
	
	NSArray *views = [self viewsForXPath:viewXPath];
	if([views count] != 1)
	{
		fprintf(
				stderr,
				"### 'viewXPath' for command 'scrollToRow' selected %d nodes, where exactly 1 is required.\n",
				[views count]);
		exit(1);
	}
	if(![[views objectAtIndex:0] isKindOfClass:[UITableView class]])
	{
		fprintf(
				stderr,
				"### 'viewXPath' for command 'scrollToRow' selected a node but it wasn't a UITableView as required.\n",
				[views count]);
		exit(1);
	}
	
	UITableView *view = [views objectAtIndex:0];
	[view
	 scrollToRowAtIndexPath:indexPath
	 atScrollPosition:UITableViewScrollPositionNone
	 animated:NO];
	
}

//
// assertText
//
// This command asserts if expected text matches the text of an UITextField or any component with text attribute
// found with the given XPath query.
//
// Required parameters:
//	viewXPath (search for views matching this XPath)
//	text (the expected text)
//
- (void) assertText: (NSDictionary *) command  {
	NSString *viewXPath = [command objectForKey:@"viewXPath"];
	if (viewXPath == nil)
	{
		fprintf(stderr, "### Command 'assertText' requires 'viewXPath' parameter.\n");
		exit(1);
	}
	
	NSString *text = [command objectForKey:@"text"];
	if (text == nil)
	{
		fprintf(stderr, "### Command 'assertText' requires 'text' parameter.\n");
		exit(1);
	}
	
	printf("=== assertText\n    viewXPath:\n        %s\n    text: %s\n",
		   [viewXPath cStringUsingEncoding:NSUTF8StringEncoding],
		   [text cStringUsingEncoding:NSUTF8StringEncoding]);
	
	NSArray *views = [self viewsForXPath:viewXPath];
	if([views count] != 1)
	{
		fprintf(
				stderr,
				"### 'viewXPath' for command 'assertText' selected %d nodes, where exactly 1 is required.\n",
				[views count]);
		exit(1);
	}
	
	UIView *viewForText = (UIView *)[views objectAtIndex:0];
	if([viewForText respondsToSelector:@selector(text)]) {
		NSString *actualText = (NSString *)[viewForText performSelector:@selector(text)];
		if(![text isEqualToString:actualText]) {
			fprintf(
					stderr,
					"### '%s' found, but '%s' was expected.\n",
					[actualText cStringUsingEncoding:NSUTF8StringEncoding],
					[text cStringUsingEncoding:NSUTF8StringEncoding],
					[views count]);
			exit(1);
			
		}
	}
	else {
		fprintf(
				stderr,
				"### %s doesn't suport 'text' method.\n",
				[viewForText.className cStringUsingEncoding:NSUTF8StringEncoding],
				[views count]);
		exit(1);
	}
}


//
// setText
//
// This command sets the text of an UITextField or any component with text attribute
// found with the given XPath query.
//
// Required parameters:
//	viewXPath (search for views matching this XPath)
//	text (the text to be set)
//
- (void) setText: (NSDictionary *) command  {
	NSString *viewXPath = [command objectForKey:@"viewXPath"];
	if (viewXPath == nil)
	{
		fprintf(stderr, "### Command 'setText' requires 'viewXPath' parameter.\n");
		exit(1);
	}
	
	NSString *text = [command objectForKey:@"text"];
	if (text == nil)
	{
		fprintf(stderr, "### Command 'setText' requires 'text' parameter.\n");
		exit(1);
	}
	
	printf("=== setText\n    viewXPath:\n        %s\n    text: %s\n",
		   [viewXPath cStringUsingEncoding:NSUTF8StringEncoding],
		   [text cStringUsingEncoding:NSUTF8StringEncoding]);
	
	NSArray *views = [self viewsForXPath:viewXPath];
	if([views count] != 1)
	{
		fprintf(
				stderr,
				"### 'viewXPath' for command 'setText' selected %d nodes, where exactly 1 is required.\n",
				[views count]);
		exit(1);
	}
	
	UIView *viewForText = (UIView *)[views objectAtIndex:0];
	if([viewForText respondsToSelector:@selector(setText:)]) {
		[viewForText performSelector:@selector(setText:) withObject:text];
	}
	else {
		fprintf(
				stderr,
				"### %s doesn't suport 'setText' method.\n",
				[viewForText.className cStringUsingEncoding:NSUTF8StringEncoding],
				[views count]);
		exit(1);
	}
}

//
// pause
//
// This command keeps does nothing except setting the minimum interval
// to the next command according to the 'seconds' parameter
//
// Required parameters:
//	seconds (interval between pause and the next command)
//
- (void) pause: (NSDictionary *) command  {
	NSNumber *seconds = [command objectForKey:@"seconds"];
	if (seconds == nil) {
		fprintf(stderr, "### Command 'pause' requires 'seconds' parameter.\n");
		exit(1);
		
	}
	printf("=== pause\n    seconds:\n        %f\n",
		   [seconds floatValue]);
	
	scriptRunnerInterCommandDelay = [seconds floatValue];
}

#pragma mark -

//
// runCommand
//
// Runs the first command in the scriptCommands array and then removes it from
// the array.
//
// Two commands are supported:
//	- outputView (writes the XML for a view hierarchy to a file)
//	- simulateTouch (selects a UIView by XPath and simulates a touch within it)
//
- (void)runCommand {
	NSDictionary *command = [scriptCommands objectAtIndex:0];
	NSString *commandName = [[command objectForKey:@"command"] stringByAppendingString:@":"];
	
	//reset default inteval
	scriptRunnerInterCommandDelay = SCRIPT_RUNNER_INTER_COMMAND_DELAY;
	
	if([self respondsToSelector:NSSelectorFromString(commandName)])
		[self performSelector:NSSelectorFromString(commandName) withObject:command];
	else {
		fprintf(
				stderr,
				"### command '%s' doesn't exist. See ScriptRunner.m\n",
				[commandName UTF8String]);
		exit(1);
	}
	//
	// Remove each command after execution
	//
	[scriptCommands removeObjectAtIndex:0];
	
	//
	// Exit the program when complete
	//
/*	if ([scriptCommands count] == 0)
	{
		[self release];
		exit(0);
	}
	else
	{
*/		//
		// If further commands remain, queue the next one
		//
		[self
		 performSelector:@selector(runCommand)
		 withObject:nil
		 afterDelay:scriptRunnerInterCommandDelay];
//	}
}


- (void)runScript {
	
	//	No current commands, start processing the next file
	if ((scriptCommands == nil) || ([scriptCommands count] == 0)) {
		
		//	If there are no more commands and no more scripts, terminate
		if ([scriptList count] == 0) {
			NSLog(@"\n\n****\nFinished processing Bromine Suite of Scripts\n****\n\n");
			exit(0);
		}

		//	If there is a current name, give a done message
		if (self.currentScriptName) {
			NSLog(@"Done Running Bromine Script - %@", self.currentScriptName);
		}
		
		//	Otherwise process the next file in the list
		NSString	*scriptPath = [scriptList objectAtIndex:0];
		self.currentScriptName = [[scriptPath lastPathComponent] stringByDeletingPathExtension];
		NSLog(@"Starting Bromine Script - %@", self.currentScriptName);
		
		//	Get the file contents and validate that they are not empty
		NSData	*scriptData = [NSData dataWithContentsOfFile:scriptPath];
		NSAssert(scriptData != nil, @"The contents of the Bromine script:\n%@\n\t were empty");
		
		//	Parse out the object and assert that it is any array
		scriptCommands = [[NSPropertyListSerialization propertyListFromData:scriptData mutabilityOption:NSPropertyListMutableContainers format:nil errorDescription:nil] retain];
		NSAssert([scriptCommands count] > 0, @"There are no values to run in the Bromine script: %@", self.currentScriptName);
		
		//	Start Processing the file
		[self runCommand];
		
		//	Reomve this script from the list
		[scriptList removeObjectAtIndex:0];
		
	}
	
	//	Always run again after 5 seconds
	[self performSelector:@selector(runScript) withObject:nil afterDelay:5.0f];
	
}

@end

#endif

