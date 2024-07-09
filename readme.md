[![Build Status](https://travis-ci.org/coldbox-modules/sentry.svg?branch=development)](https://travis-ci.org/coldbox-modules/sentry)

# Welcome to the Sentry Module

This module connects your CFML application to send bug reports to Sentry (https://sentry.io)

## LICENSE

Apache License, Version 2.0.

## IMPORTANT LINKS

- Source: https://github.com/coldbox-modules/sentry
- Issues: https://github.com/coldbox-modules/sentry/issues
- Account Setup: https://sentry.io
- [Changelog](changelog.md)

## SYSTEM REQUIREMENTS

- Adobe ColdFusion 2016+
- Lucee 5

## Instructions

Just drop into your modules folder or use the `box` cli to install

```bash
box install sentry
```

## Updating to Version 2

Version 2 of this module includes some potentially breaking changes in how the event data that is sent to Sentry is constructed. In version 2 the events match the up to date format that Sentry has adopted for their official SDKs. If you are not sending your events to the Sentry hosted service, but using a self-hosted Sentry instance, please be sure you are running an up to date version of the Sentry service before updating to version 2 of this module.

Additionally, Sentry has deprecated sending events to the `/api/{project_id}/store` endpoint in favor of a new `/api/{project_id}/envelope` endpoint (and a new structure for the body of the post requests). Again, if you self-host an older version of the Sentry service, sending events to the `store` endpoint might be your only option. There is a new module setting, `sentryEventEndpoint`, that defaults to `store`, but can be set to `envelope` to enable sending events to the modern endpoint.

## CFML App Installation

If your app uses neither ColdBox nor LogBox, you can still instantiate the `SentryService` and use it directly so long as you prep it with the settings it needs.

```js
// Create Sentry service and load it with data
application.sentryService = new modules.sentry.models.SentryService( {
  async : true,
  DSN : 'https://xxxxxxxxxx@sentry.io/3'
} );

// Send a log message
application.sentryService.captureMessage( 'winter is coming', 'warning' );

// Send an exception
application.sentryService.captureException( exception=cfcatch, additionalData={ anything : 'here' } );
```

This module makes use of the `funclinenums` module for the purpose of computing and reporting CFML function names in a stack trace. If you installed this via CommandBox, `funclinenums` was installed as a dependency for you. In a ColdBox app you don't need to do anything more, as WireBox will take care of wiring it up for you. However, in a non ColdBox app, if you want CFML function names reported in your stack trace you will need to add it to the `SentryService` yourself.

```cfc
functionLineNums = new modules.sentry.modules.funclinenums.functionLineNums();
application.sentryService.setFunctionLineNums(functionLineNums);
```

## LogBox Standalone Installation

If your app doesn't use ColdBox but does use LogBox, you can use our `SentryAppender` class in your LogBox config.  You'll need to still instantiate the `SentryService` the same as above, but then you can just use the standard LogBox API to send your messages.

This means if your app already has LogBox calls in place, simply adding the Sentry appender will start sending all those messages to Sentry without any app code changes on your part.  

Here is an example LogBox standalone config file

**MyLogBoxConfig.cfc**
```js
component {
  function configure() {
    logBox = {
      appenders : {
        sentry : {
          class : 'modules.sentry.models.SentryAppender',
          levelMax : 'WARN',
          properties : {
            sentryService : new sentry.models.SentryService( {
              async : true,
              DSN : 'https://xxxxxxxxxx@sentry.io/3'
            } )                      
          }
        }
      },
      root : { levelMax : 'INFO', appenders : '*' },
      categories = {}
    };
  }
}
```

Then create LogBox as normal and send your messages:
```js
application.logbox = new logbox.system.logging.LogBox(
	new logbox.system.logging.config.LogBoxConfig( CFCConfigPath="config.MyLogBoxConfig" ) 
);

// Send a log message
application.logbox.getRootLogger().warn( 'winter is coming' );

// Send an exception
application.logbox.getRootLogger().error( message='Boom boom', extraInfo=cfcatch );

// Send an exception plus other stuff
application.logbox.getRootLogger().error( message='Boom boom', extraInfo={ exception: cfcatch, anything: 'here', as : 'well' );
```

The `extraInfo` is optional, but if it is a cfcatch object or a struct containing a cfcatch object in a key called `exception`, the appender will use special treatment of the exception object.  Both of the examples above will extract the cfcatch and log to Sentry as an error which contain additional information over a simple text log message.

## ColdBox Installation

Lucky you, ColdBox provides you with the "easy street" method of using this module.  By just installing the module, the following things will happen automatically for you:
* The Sentry LogBox appender we showed above will be registered to capture all messages of FATAL or ERROR severity
* An `onException` interceptor will be registered to log all errors that ColdBox sees.

The only required configuration is your client DSN or auth keys so we can contact Sentry.  This configuration goes in `/config/ColdBox.cfc` in `moduleSettings.sentry` like so:

 ```js
moduleSettings = {
  sentry : {
    async : true,
    DSN : 'https://xxxxxxxxxx@sentry.io/3'
  }
};
```

## Settings

Regardless of the installation method above, the settings for Sentry are mostly the same.  Here is the full list.  Note, `enableLogBoxAppender`, `levelMin`, `levelMax`, and `enableExceptionLogging` are only used in when installing Sentry into a ColdBox app.
The default values are shown below.  Any settings you omit will use the default values.  

```js
settings = {
  // Enable the Sentry LogBox Appender Bridge
  enableLogBoxAppender : true,
  // Min/Max levels for appender
  levelMin : 'FATAL',
  levelMax : 'ERROR',
  // auto-register onException interceptor
  enableExceptionLogging : true,
  // Send messages to Sentry in a thread
  async : true,
  // Don't sent URL or FORM field values of these names to Sentry
  scrubFields : [ 'passwd', 'password', 'password_confirmation', 'secret', 'confirm_password', 'secret_token', 'APIToken', 'x-api-token', 'fwreinit' ],
  // Don't sent HTTP header values of these names to Sentry
  scrubHeaders : [ 'x-api-token', 'Authorization' ],
  // The current release of your app, used with Sentry release/deploy tracking. Ex. "myApp@2.3.0"
  release : '',
  // App environment, used to control notifications and filtering
  environment : 'production',
  // Client connection string for this project. Mutually exclusive with next 4 settings
  // Get this from the "settings" page on a project under "Client Keys (DSN)" 
  DSN : '',
  // Sentry public client key for this project. (Not needed when using DSN)
  publicKey : '',
  // Sentry public client key for this project (Not needed when using DSN)
  privateKey : '',
  // Sentry projectID (Not needed when using DSN)
  projectID : 0,
  // URL of your Sentry server (Not needed when using DSN)
  sentryUrl : 'https://sentry.io',
  // posting to "#sentryUrl#/api/#projectID#/store" is deprecated, but backward compatible
  // set to "envelope" to send events to modern "#sentryUrl#/api/#projectID#/envelope"
  sentryEventEndpoint : "store",
  // name of your server
  serverName : cgi.server_name,
  // Absolute path to the root of your app, defaults to the webroot.
  // files in stacktrace frames contained under this path will be reported relative to it
  appRoot : expandPath('/'),
  // Default logger category. LogBox appender will pass through the LogBox category name 
  logger : 'sentry',
  // Closure to return dynamic info of logged in user which will appear in Sentry error reports under "User".
  // No args are passed to the closure when used outside of a ColdBox app. 
  userInfoUDF : function( event, rc, prc ){
    return {
      // Standard user data Sentry looks for
      id : 123
      username : 'bwood',
      email : 'brad@bradwood.com',
      // Anything else you want
      cool : true,
      memberType : 'platinum'
    };
  }
}
```

### Credit

This project is based on the fine open source work of others.  

* https://github.com/GiancarloGomez/sentry-cfml
* https://github.com/jmacul2/raven-cfml

********************************************************************************
Copyright Since 2005 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.ortussolutions.com
********************************************************************************

#### HONOR GOES TO GOD ABOVE ALL

Because of His grace, this project exists. If you don't like this, then don't read it, its not for you.

> "Therefore being justified by faith, we have peace with God through our Lord Jesus Christ:
By whom also we have access by faith into this grace wherein we stand, and rejoice in hope of the glory of God.
And not only so, but we glory in tribulations also: knowing that tribulation worketh patience;
And patience, experience; and experience, hope:
And hope maketh not ashamed; because the love of God is shed abroad in our hearts by the 
Holy Ghost which is given unto us. ." Romans 5:5

### THE DAILY BREAD

 > "I am the way, and the truth, and the life; no one comes to the Father, but by me (JESUS)" Jn 14:1-12
