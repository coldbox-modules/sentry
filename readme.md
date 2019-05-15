[![Build Status](https://travis-ci.org/coldbox-modules/sentry.svg?branch=development)](https://travis-ci.org/coldbox-modules/sentry)

# Welcome to the Sentry Module

This module connects your ColdBox application to send bug reports and even LogBox integration into Sentry (https://sentry.io)

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

## Settings

Create the `sentry` structure inside the `moduleSettings` struct in your `config/Coldbox.cfc`:

```js
moduleSettings = {
     sentry = {
         // Enable the Sentry LogBox Appender Bridge
         "enableLogBoxAppender" : true,
         // Enable/disable error logging
         "enableExceptionLogging" = true,
         "publicKey" : getSystemSetting( "SENTRY_PUBLICKEY", "" ),
         "privateKey" : getSystemSetting( "SENTRY_PRIVATEKEY", "" ),
         "projectID" : 1,
         async : true,
         // Closure to return dynamic info of logged in user
         userInfoUDF = function(){
             return {
             	 // Standard user data Sentry looks for
             	 id : 123
                 username : 'woodsb',
                 email : 'brad@bradwood.com',
                 // Anything else you want
                 cool : true
             };
         }
     }
}
```

## Usage

Just by activating the module any exceptions will be sent to Sentry. The LogBox appender bridge is **activated** by default, and the Sentry appender is added as an appender to your application.  You can fine tune it via your main ColdBox logbox configuration file.

### Exception Tracking

The module will automatically listen for exceptions in any part of your application and send the exceptions over to sentry.

### Logging

You can use LogBox and any of its logging methods to send data to Sentry automatically using the required logging levels for the appender in the configuration.

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
