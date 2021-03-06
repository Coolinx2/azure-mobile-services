// ----------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ----------------------------------------------------------------------------

#import "MSURLBuilder.h"
#import "MSPredicateTranslator.h"


#pragma mark * Query String Constants


NSString *const topParameter = @"$top";
NSString *const skipParameter = @"$skip";
NSString *const selectParameter = @"$select";
NSString *const orderByParameter = @"$orderby";
NSString *const orderByAscendingFormat = @"%@ asc";
NSString *const orderByDescendingFormat = @"%@ desc";
NSString *const filterParameter = @"$filter";
NSString *const inlineCountParameter = @"$inlinecount";
NSString *const inlineCountAllPage = @"allpages";
NSString *const inlineCountNone = @"none";
#pragma mark * MSURLBuilder Implementation


@implementation MSURLBuilder


#pragma mark * Public URL Builder Methods

+ (NSURL *) addTableSystemProperties:(MSTable *)table toURL:(NSURL *)url
{
    if (table.systemProperties == MSSystemPropertyNone) {
        return url;
    }

    if(url.query != nil && [url.query rangeOfString:@"__systemProperties" options:NSCaseInsensitiveSearch].location != NSNotFound)
    {
        return url;
    }
                               
    NSString *value = @"";
    if(table.systemProperties == MSSystemPropertyAll) {
        value = encodeToPercentEscapeString(@"*");
    } else {
        NSMutableArray *properties = [NSMutableArray array];
        if (table.systemProperties & MSSystemPropertyCreatedAt)
        {
            [properties addObject:@"__createdAt"];
        }
        if (table.systemProperties & MSSystemPropertyUpdatedAt)
        {
            [properties addObject:@"__updatedAt"];
        }
        if (table.systemProperties & MSSystemPropertyVersion)
        {
            [properties addObject:@"__version"];
        }
        value = [properties componentsJoinedByString:@","];
    }
    
    return [MSURLBuilder URLByAppendingQueryString:[@"__systemProperties=" stringByAppendingString:value] toURL:url];
}

+(NSURL *) URLForTable:(MSTable *)table
            parameters:(NSDictionary *)parameters
                 query:( NSString *)query
               orError:(NSError **)error
{
    NSURL *url = nil;
    
    // Ensure that the user parameters are valid if there are any
    if ([MSURLBuilder userParametersAreValid:parameters orError:error]) {
        
        // Create the table path
        NSString *tablePath = [NSString stringWithFormat:@"tables/%@", table.name];
        
        // Append it to the application URL; Don't percent encode the tablePath
        // because URLByAppending will percent encode for us
        url = [table.client.applicationURL URLByAppendingPathComponent:tablePath];
        
        // Add on the querystring now
        url = [MSURLBuilder URLByAppendingQueryString:query toURL:url];
            
        // Add the query parameters if any
        url = [MSURLBuilder URLByAppendingQueryParameters:parameters
                                                    toURL:url];
        
        // Check if we should add in system properties
        url = [MSURLBuilder addTableSystemProperties:table toURL:url];
    }
    
    return url;
}

+(NSURL *) URLForTable:(MSTable *)table
        parameters:(NSDictionary *)parameters
               orError:(NSError **)error
{
    return [MSURLBuilder URLForTable:table parameters:parameters query:nil orError:error];
}

+(NSURL *) URLForTable:(MSTable *)table
      itemIdString:(NSString *)itemId
        parameters:(NSDictionary *)parameters
               orError:(NSError **)error
{        
    // Get the URL for the table
    NSURL *url = [self URLForTable:table
                    parameters:parameters
                           orError:error];
    
    // Add the itemId; NSURL will do the right thing and account for the
    // query string if there is one
    if (itemId) {
        url = [url URLByAppendingPathComponent:itemId];
    }
    
    return url;
}

+(NSURL *) URLForTable:(MSTable *)table query:(NSString *)query
{
    // Get the URL for the table; no need to pass in the error parameter because
    // only user-parameters can cause an error
    return [self URLForTable:table parameters:nil query:query orError:nil];
}

+(NSURL *)URLForApi:(MSClient *)client
            APIName:(NSString *)APIName
            parameters:(NSDictionary *)parameters
               orError:(NSError **)error
{
    NSURL *url = nil;
    
    // Ensure that the user parameters are valid if there are any
    if ([MSURLBuilder userParametersAreValid:parameters orError:error]) {
        
        // Treat nil APIName as an empty string
        if (!APIName) {
            APIName = @"";
        }
        
        // Create the API path
        NSString *apiPath = [NSString stringWithFormat:@"api/%@", APIName];
        
        // Check for a query string in the APIName
        NSString *apiQuery = nil;
        NSUInteger queryStringStart = [apiPath rangeOfString:@"?"].location;
        if (queryStringStart != NSNotFound) {
            apiQuery = [apiPath substringFromIndex:queryStringStart + 1];
            apiPath = [apiPath substringToIndex:queryStringStart];
        }
        
        // Append it to the application URL; Don't percent encode the apiPath
        // because URLByAppending will percent encode for us
        url = [client.applicationURL URLByAppendingPathComponent:apiPath];
        
        // If there was a query on the APIName, add it back to the url
        // we are building
        if (apiQuery) {
            url = [MSURLBuilder URLByAppendingQueryString:apiQuery toURL:url];
        }
        
        // Add the query parameters if any
        url = [MSURLBuilder URLByAppendingQueryParameters:parameters
                                                    toURL:url];
    }
    
    return url;
}

+(NSString *) queryStringFromQuery:(MSQuery *)query
                           orError:(NSError **)error;
{
    NSString *queryString = nil;
    NSString *filterValue = nil;
    
    // Ensure that the user parameters are valid if there are any
    if ([MSURLBuilder userParametersAreValid:[query parameters] orError:error]) {
        
        if (query.predicate) {
            // Translate the predicate into the filter first since it might error
            filterValue = [MSPredicateTranslator
                           queryFilterFromPredicate:query.predicate
                           orError:error];
        }
        
        if (filterValue || !query.predicate) {
            
            // Create a dictionary to hold all of the query parameters
            NSMutableDictionary *queryParameters = [NSMutableDictionary dictionary];
            
            // Add the $filter parameter
            if (query.predicate) {
                [queryParameters setValue:filterValue forKey:filterParameter];
            }
            
            // Add the $top parameter
            if (query.fetchLimit >= 0) {
                NSString *topValue = [NSString stringWithFormat:@"%ld",
                                      (long)query.fetchLimit];
                [queryParameters setValue:topValue forKey:topParameter];
            }
            
            // Add the $skip parameter
            if (query.fetchOffset >= 0) {
                NSString *skipValue = [NSString stringWithFormat:@"%ld",
                                       (long)query.fetchOffset];
                [queryParameters setValue:skipValue forKey:skipParameter];
            }
            
            // Add the $select parameter
            if (query.selectFields) {
                NSString *selectFieldsValue = [query.selectFields
                                               componentsJoinedByString:@","];
                [queryParameters setValue:selectFieldsValue forKey:selectParameter];
            }
            
            // Add the $orderBy parameter
            if (query.orderBy) {
                NSMutableString *orderByString = [NSMutableString string];
                for (NSSortDescriptor* sort in query.orderBy){
                    if (orderByString.length > 0) {
                        [orderByString appendString:@","];
                    }
                    NSString *format = (sort.ascending) ?
                    orderByAscendingFormat :
                    orderByDescendingFormat;
                    [orderByString appendFormat:format, sort.key];
                }
                [queryParameters setValue:orderByString forKey:orderByParameter];
            }
            
            // Add the $inlineCount parameter
            NSString *includeTotalCountValue = query.includeTotalCount ?
            inlineCountAllPage :
            inlineCountNone;
            [queryParameters setValue:includeTotalCountValue
                               forKey:inlineCountParameter];
            
            // Add the user parameters
            if (query.parameters) {
                [queryParameters addEntriesFromDictionary:query.parameters];
            }
            
            queryString = [MSURLBuilder queryStringFromParameters:queryParameters];
        }
    }
    
    return queryString;
}


#pragma mark * Private Methods


// This is for 'strict' URL encoding that will encode even reserved URL
// characters.  It should be used only on URL pieces, not full URLs.
NSString* encodeToPercentEscapeString(NSString *string) {
    return (__bridge_transfer NSString *)
    CFURLCreateStringByAddingPercentEscapes(NULL,
                                            (CFStringRef) string,
                                            NULL,
                                            (CFStringRef) @"!*;:@&=+/?%#[]",
                                            kCFStringEncodingUTF8);
}

+(NSString *) queryStringFromParameters:(NSDictionary *)queryParameters
{
    // Iterate through the parameters to build the query string as key=value
    // pairs seperated by '&'
    NSMutableString *queryString = [NSMutableString string];
    for (NSString* key in [queryParameters allKeys]){
        
        // Get the paremeter name and value
        NSString *value = [[queryParameters objectForKey:key] description];
        NSString *name = [key description];
        
        // URL Encode the parameter name and the value
        NSString *encodedValue = encodeToPercentEscapeString(value);
        NSString *encodedName = encodeToPercentEscapeString(name);

        if (queryString.length > 0) {
            [queryString appendString:@"&"];
        }
        
        [queryString appendFormat:@"%@=%@", encodedName, encodedValue];
    }
    
    return queryString;
}

+(NSURL *) URLByAppendingQueryParameters:(NSDictionary *)queryParameters
                                   toURL:(NSURL *)url
{
    NSURL *newUrl = url;
    
    // Do nothing if there are no query paramters
    if (queryParameters && queryParameters.count > 0) {
        
        NSString *queryString =
            [MSURLBuilder queryStringFromParameters:queryParameters];
        newUrl = [MSURLBuilder URLByAppendingQueryString:queryString
                                                        toURL:newUrl];
    }
    
    return newUrl;
}

+(NSURL *) URLByAppendingQueryString:(NSString *)queryString
                               toURL:(NSURL *)url
{
    NSURL *newUrl = url;
    
    // Do nothing if the parameters were empty strings
    if (queryString && queryString.length > 0) {
        
        // Check if we are appending to existing parameters or not
        BOOL alreadyHasQuery = url.query != nil;
        NSString *queryChar = alreadyHasQuery ? @"&" : @"?";
        
        // Rebuild a new URL from a string
        NSString *newUrlString = [NSString stringWithFormat:@"%@%@%@",
                                  [url absoluteString],
                                  queryChar,
                                  queryString];
        
        newUrl = [NSURL URLWithString:newUrlString];
    }
    
    return newUrl;
}

+(BOOL) userParametersAreValid:(NSDictionary *)parameters
                       orError:(NSError **)error
{
    BOOL areValid = YES;
    NSError *localError = nil;
    
    // Do nothing if there are no query paramters
    if (parameters && parameters.count > 0) {
       
        for (NSString* key in [parameters allKeys]){
            
            // Ensure none of the user parameters start with the '$', as this
            // is reserved for system-defined query parameters
            if ([key length] > 0 && [key characterAtIndex:0] == '$') {
                localError = [MSURLBuilder errorWithUserParameter:key];
                areValid = NO;
                break;
            }
        }
    }
    
    if (!areValid && error) {
        *error = localError;
    }
    
    return areValid;
}


#pragma mark * Private NSError Generation Methods


+(NSError *) errorWithUserParameter:(NSString *)parameterName
{
    NSString *descriptionKey = @"'%@' is an invalid user-defined query string parameter. User-defined query string parameters must not begin with a '$'.";
    NSString *descriptionFormat = NSLocalizedString(descriptionKey, nil);
    NSString *description = [NSString stringWithFormat:descriptionFormat, parameterName];
    NSDictionary *userInfo = @{ NSLocalizedDescriptionKey :description };
    
    return [NSError errorWithDomain:MSErrorDomain
                               code:MSInvalidUserParameterWithRequest
                           userInfo:userInfo];
}

@end
