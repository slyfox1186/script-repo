#!/usr/bin/env bash

clear

# You must run the script with root/admin privileges
# If not run as root the below if command will restart
# The script with root permissions
if [ "${EUID}" -ne '0' ]; then
    printf "%s\n\n" 'You must run this script as root/sudo'
    exit 1
fi

# You need to customize each variable below with your own values to optimize squid's performance
# You can add, remove, or modify this script as needed

# Create required directories
if [ ! -d /etc/squid ]; then
    sudo mkdir -p /etc/squid
fi

# Check squid current status
if ! systemctl status squid.service; then
    printf "%s\n\n%s\n\n" \
        'The squid service needs to be running to continue.'
        'The script will attempt to start squid now... please be patient.'
    sudo service squid start
fi
if ! service squid start; then
    printf "%s\n\n%s\n\n" \
        'The script was unable to start the squid service. You should manually change any errors'
        'in the squid.conf file which is usually located in "/etc/squid/squid.conf"'
    exit 1
else
    clear
    printf "%s\n\n" 'Started Squid'
    sleep 2
    clear
fi

# Set default user/owner of squid (the ubuntu and debian default is proxy)
squid_user=proxy
hostname=homebridge

# Set how long squid waits to fully shutdown after receiving a sigterm command
# The numbers must be combined with time units of measurement aka 'seconds, minutes, hours'
# The default is 30 seconds
sd_tout='5 seconds'

# Disable persistent connections with servers while leaving
# Persistent connections with clients enabled to avoid connection
# Issues.
client_pcons=on
server_pcons=off

####################
## Cache SETTINGS ##
####################

# Set cache directory path
cache_dir_squid=/var/spool/squid
# Cache dir squid size units in mb
cache_dir_squid_size=1000
cache_swp_high=95
cache_swp_low=90
# Memory cache mode options [ always | disk ]
mem_cache_mode=always
# Cache memory transit file allocation max size limit (can be increased)
cache_mem='512 MB'

# Limit client requests buffer size
client_rqst_bfr_size='512 KB'

# Firewalld program ports'
squid_port=3128/tcp
pihole_port=4711/tcp

# Firewalld services (this should be considered at home settings where you trust the computers accessible to your network)
Fwld_01=dhcp
Fwld_02=dhcpv6
Fwld_03=dns
Fwld_04=http
Fwld_05=ssh

# The lan ip address of your dhcp/dns nameserver (usually your router's ip address)
dns_server_ip=192.168.1.40

# Object sizes
min_obj_size='64 bytes'
max_obj_size='1 MB'
max_obj_size_mem='1 MB'

# Squid files
basic_ncsa_auth="$(sudo find /usr/lib -type f -name basic_ncsa_auth)"
squid_config=/etc/squid/squid.conf
squid_passwords=/etc/squid/passwords
squid_whitelist=/etc/squid/whitelist.txt
squid_blacklist=/etc/squid/blacklist.txt

# Detect broken pcon settings
detect_broken_pconn=off

# Create squid.conf file
cat > "$squid_config" <<EOF
# Welcome to squid 5.2
#    ----------------------------
# This is the documentation for the squid configuration file.
# This documentation can also be found online at:
# Http://www.squid-cache.org/doc/config/
# You may wish to look at the squid home page and wiki for the
# Faq and other documentation:
# Http://www.squid-cache.org/
# Http://wiki.squid-cache.org/squidfaq
# Http://wiki.squid-cache.org/configexamples
# This documentation shows what the defaults for various directives
# Happen to be.  if you don't need to change the default, you should
# Leave the line out of your squid.conf in most cases.
# In some cases "none" refers to no default setting at all,
# While in other cases it refers to the value of the option
#    - the comments for that keyword indicate if this is the case.

# Configuration options can be included using the "include" directive.
# Include takes a list of files to include. quoting and wildcards are
# Supported.
# For example,
# Include /path/to/included/file/squid.acl.config
# Includes can be nested up to a hard-coded depth of 16 levels.
# This arbitrary restriction is to prevent recursive include references
# From causing squid entering an infinite loop whilst trying to load
# Configuration files.
# Values with byte units
# Squid accepts size units on some size-related directives. all
# Such directives are documented with a default value displaying
# A unit.
# Units accepted by squid are:
# Bytes - byte
# Kb - kilobyte (1024 bytes)
# Mb - megabyte
# Gb - gigabyte
# Values with time units
# Time-related directives marked with either "time-units" or
#    "time-units-small" accept a time unit. The supported time units are:
# Nanosecond (time-units-small only)
# Microsecond (time-units-small only)
# Millisecond
# Second
# Minute
# Hour
# Day
# Week
# Fortnight
# Month - 30 days
# Year - 31557790080 milliseconds (just over 365 days)
# Decade
# Values with spaces, quotes, and other special characters
# Squid supports directive parameters with spaces, quotes, and other
# Special characters. surround such parameters with "double quotes". use
# The configuration_includes_quoted_values directive to enable or
# Disable that support.
# Squid supports reading configuration option parameters from external
# Files using the syntax:
# Parameters("/path/filename")
# For example:
# Acl allowlist dstdomain parameters("/etc/squid/allowlist.txt")
# Conditional configuration
# If-statements can be used to make configuration directives
# Depend on conditions:
# If <condition>
#            ... regular configuration directives ...
#        [else
#            ... regular configuration directives ...]
# Endif
# The else part is optional. the keywords "if", "else", and "endif"
# Must be typed on their own lines, as if they were regular
# Configuration directives.
# Note: an else-if condition is not supported.
# These individual conditions types are supported:
# True
# Always evaluates to true.
# False
# Always evaluates to false.
#        <integer> = <integer>
# Equality comparison of two integer numbers.
# Smp-related macros
# The following smp-related preprocessor macros can be used.
# $process_name expands to the current squid process "name"
#    (e.g., squid1, squid2, or cache1).
# $process_number expands to the current squid process
# Identifier, which is an integer number (e.g., 1, 2, 3) unique
# Across all squid processes of the current service instance.
# $service_name expands into the current squid service instance
# Name identifier which is provided by -n on the command line.
# Logformat macros
# Logformat macros can be used in many places outside of the logformat
# Directive. in theory, all of the logformat codes can be used as %macros,
# Where they are supported. in practice, a %macro expands as a dash (-) when
# The transaction does not yet have enough information and a value is needed.
# There is no definitive list of what tokens are available at the various
# Stages of the transaction.
# And some information may already be available to squid but not yet
# Committed where the macro expansion code can access it (report
# Such instances!). the macro will be expanded into a single dash
#    ('-') in such cases. Not all macros have been tested.

# Tag: broken_vary_encoding
# This option is not yet supported by squid-3.
#Default:
# None

# Tag: cache_vary
# This option is not yet supported by squid-3.
#Default:
# None

# Tag: error_map
# This option is not yet supported by squid-3.
#Default:
# None

# Tag: external_refresh_check
# This option is not yet supported by squid-3.
#Default:
# None

# Tag: location_rewrite_program
# This option is not yet supported by squid-3.
#Default:
# None

# Tag: refresh_stale_hit
# This option is not yet supported by squid-3.
#Default:
# None

# Tag: dns_v4_first
# Remove this line. squid no longer supports the preferential treatment of dns a records.
#Default:
#Dns_v4_first

# Tag: cache_peer_domain
# Replace with dstdomain acls and cache_peer_access.
#Default:
# None

# Tag: ie_refresh
# Remove this line. the behavior enabled by this is no longer needed.
#Default:
# None

# Tag: sslproxy_cafile
# Remove this line. use tls_outgoing_options cafile= instead.
#Default:
# None

# Tag: sslproxy_capath
# Remove this line. use tls_outgoing_options capath= instead.
#Default:
# None

# Tag: sslproxy_cipher
# Remove this line. use tls_outgoing_options cipher= instead.
#Default:
# None

# Tag: sslproxy_client_certificate
# Remove this line. use tls_outgoing_options cert= instead.
#Default:
# None

# Tag: sslproxy_client_key
# Remove this line. use tls_outgoing_options key= instead.
#Default:
# None

# Tag: sslproxy_flags
# Remove this line. use tls_outgoing_options flags= instead.
#Default:
# None

# Tag: sslproxy_options
# Remove this line. use tls_outgoing_options options= instead.
#Default:
# None

# Tag: sslproxy_version
# Remove this line. use tls_outgoing_options options= instead.
#Default:
# None

# Tag: hierarchy_stoplist
# Remove this line. use always_direct or cache_peer_access acls instead if you need to prevent cache_peer use.
#Default:
# None

# Tag: log_access
# Remove this line. use acls with access_log directives to control access logging
#Default:
# None

# Tag: log_icap
# Remove this line. use acls with icap_log directives to control icap logging
#Default:
# None

# Tag: ignore_ims_on_miss
# Remove this line. the http/1.1 feature is now configured by 'cache_miss_revalidate'.
#Default:
# None

# Tag: balance_on_multiple_ip
# Remove this line. squid performs a 'happy eyeballs' algorithm, this multiple-ip algorithm is not longer relevant.
#Default:
# None

# Tag: chunked_request_body_max_size
# Remove this line. squid is now http/1.1 compliant.
#Default:
# None

# Tag: dns_v4_fallback
# Remove this line. squid performs a 'happy eyeballs' algorithm, the 'fallback' algorithm is no longer relevant.
#Default:
# None

# Tag: emulate_httpd_log
# Replace this with an access_log directive using the format 'common' or 'combined'.
#Default:
# None

# Tag: forward_log
# Use a regular access.log with acl limiting it to miss events.
#Default:
# None

# Tag: ftp_list_width
# Remove this line. configure the ftp page display using the css controls in errorpages.css instead.
#Default:
# None

# Tag: ignore_expect_100
# Remove this line. the http/1.1 feature is now fully supported by default.
#Default:
# None

# Tag: log_fqdn
# Remove this option from your config. to log fqdn use %>a in the log format.
#Default:
# Log_fqdn on (depreciated/unusable)

# Tag: log_ip_on_direct
# Remove this option from your config. to log server or peer names use %<a in the log format.
#Default:
# None

# Tag: maximum_single_addr_tries
# Replaced by connect_retries. the behavior has changed, please read the documentation before altering it.
#Default:
# None

# Tag: referer_log
# Replace this with an access_log directive using the format 'referrer'.
#Default:
# None

# Tag: update_headers
# Remove this line. the feature is supported by default in storage types where the update is implemented.
#Default:
# None

# Tag: url_rewrite_concurrency
# Remove this line. set the 'concurrency=' option of url_rewrite_children instead.
#Default:
# None

# Tag: useragent_log
# Replace this with an access_log directive using the format 'useragent'.
#Default:
# None

# Tag: dns_testnames
# Remove this line. dns is no longer tested on startup.
#Default:
# None

# Tag: extension_methods
# Remove this line. all valid methods for http are accepted by default.
#Default:
# None

# Tag: zero_buffers
#Default:
# None

# Tag: incoming_rate
#Default:
# None

# Tag: server_http11
# Remove this line. http/1.1 is supported by default.
#Default:
# None

# Tag: upgrade_http0.9
# Remove this line. icy/1.0 streaming protocol is supported by default.
#Default:
# None

# Tag: zph_local
# Alter these entries. use the qos_flows directive instead.
#Default:
# None

# Tag: header_access
# Since squid-3.0 replace with request_header_access or reply_header_access
# Depending on whether you wish to match client requests or server replies.
#Default:
# None

# Tag: httpd_accel_no_pmtu_disc
# Since squid-3.0 use the 'disable-pmtu-discovery' flag on http_port instead.
#Default:
# None

# Tag: wais_relay_host
# Replace this line with the 'cache_peer' configuration.
#Default:
# None

# Tag: wais_relay_port
# Replace this line with the 'cache_peer' configuration.
#Default:
# None

# Options for smp
# -----------------------------------------------------------------------------

# Tag: workers
# Number of main squid processes or "workers" to fork and maintain.
# 0: "no daemon" mode, like running "squid -n ..."
# 1: "no smp" mode, start one main squid process daemon (default)
# N: start n main squid process daemons (i.e., smp mode)
# In smp mode, each worker does nearly all that a single squid daemon
# Does (e.g., listen on http_port and forward http requests).
#Default:
# Smp support disabled.

# Tag: cpu_affinity_map
# Usage: cpu_affinity_map process_numbers=p1,p2,... cores=c1,c2,...
# Sets 1:1 mapping between squid processes and cpu cores. for example,
# Cpu_affinity_map process_numbers=1,2,3,4 cores=1,3,5,7
# Affects processes 1 through 4 only and places them on the first
# Four even cores, starting with core #1.
# Cpu cores are numbered starting from 1. requires support for
# Sched_getaffinity(2) and sched_setaffinity(2) system calls.
# Multiple cpu_affinity_map options are merged.
# See also: workers
#Default:
# Let the operating system decide.

# Tag: shared_memory_locking    on|off
# Whether to ensure that all required shared memory is available by
#    "locking" that shared memory into RAM when Squid starts. The
# Alternative is faster startup time followed by slightly slower
# Performance and, if not enough ram is actually available during
# Runtime, mysterious crashes.
# Smp squid uses many shared memory segments. these segments are
# Brought into squid memory space using an mmap(2) system call. during
# Squid startup, the mmap() call often succeeds regardless of whether
# The system has enough ram. in general, squid cannot tell whether the
# Kernel applies this "optimistic" memory allocation policy (but
# Popular modern kernels usually use it).
# Later, if squid attempts to actually access the mapped memory
# Regions beyond what the kernel is willing to allocate, the
#    "optimistic" kernel simply kills Squid kid with a SIGBUS signal.
# Some of the memory limits enforced by the kernel are currently
# Poorly understood: we do not know how to detect and check them. this
# Option ensures that the mapped memory will be available.
# This option may have a positive performance side-effect: locking
# Memory at the start avoids runtime paging i/o. paging slows squid down.
# Locking memory may require a large enough rlimit_memlock os limit,
# Cap_ipc_lock capability, or equivalent.
#Default:
# Shared_memory_locking off

# Tag: hopeless_kid_revival_delay    time-units
# Normally, when a kid process dies, squid immediately restarts the
# Kid. a kid experiencing frequent deaths is marked as "hopeless" for
# The duration specified by this directive. hopeless kids are not
# Automatically restarted.
# Currently, zero values are not supported because they result in
# Misconfigured smp squid instances running forever, endlessly
# Restarting each dying kid. to effectively disable hopeless kids
# Revival, set the delay to a huge value (e.g., 1 year).
# Reconfiguration also clears all hopeless kids designations, allowing
# For manual revival of hopeless kids.
#Default:
# Hopeless_kid_revival_delay 1 hour

# Options for authentication
# -----------------------------------------------------------------------------

# Tag: auth_param
# This is used to define parameters for the various authentication
# Schemes supported by squid.
# Format: auth_param scheme parameter [setting]
# The order in which authentication schemes are presented to the client is
# Dependent on the order the scheme first appears in config file. ie
# Has a bug (it's not rfc 2617 compliant) in that it will use the basic
# Scheme if basic is the first entry presented, even if more secure
# Schemes are presented. for now use the order in the recommended
# Settings section below. if other browsers have difficulties (don't
# Recognize the schemes offered even if you are using basic) either
# Put basic first, or disable the other schemes (by commenting out their
# Program entry).
# Once an authentication scheme is fully configured, it can only be
# Shutdown by shutting squid down and restarting. changes can be made on
# The fly and activated with a reconfigure. i.e. you can change to a
# Different helper, but not unconfigure the helper completely.
# Please note that while this directive defines how squid processes
# Authentication it does not automatically activate authentication.
# To use authentication you must in addition make use of acls based
# On login name in http_access (proxy_auth, proxy_auth_regex or
# External with %login used in the format tag). the browser will be
# Challenged for authentication on the first such acl encountered
# In http_access processing and will also be re-challenged for new
# Login credentials if the request is being denied by a proxy_auth
# Type acl.
# Warning: authentication can't be used in a transparently intercepting
# Proxy as the client then thinks it is talking to an origin server and
# Not the proxy. this is a limitation of bending the tcp/ip protocol to
# Transparently intercepting port 80, not a limitation in squid.
# Ports flagged 'transparent', 'intercept', or 'tproxy' have
# Authentication disabled.
# === parameters common to all schemes. ===
# "program" cmdline
# Specifies the command for the external authenticator.
# By default, each authentication scheme is not used unless a
# Program is specified.
# See http://wiki.squid-cache.org/features/addonhelpers for
# More details on helper operations and creating your own.
# "key_extras" format
# Specifies a string to be append to request line format for
# The authentication helper. "quoted" format values may contain
# Spaces and logformat %macros. in theory, any logformat %macro
# Can be used. in practice, a %macro expands as a dash (-) if
# The helper request is sent before the required macro
# Information is available to squid.
# By default, squid uses request formats provided in
# Scheme-specific examples below (search for %credentials).
# The expanded key_extras value is added to the squid credentials
# Cache and, hence, will affect authentication. it can be used to
# Autenticate different users with identical user names (e.g.,
# When user authentication depends on http_port).
# Avoid adding frequently changing information to key_extras. for
# Example, if you add user source ip, and it changes frequently
# In your environment, then max_user_ip acl is going to treat
# Every user+ip combination as a unique "user", breaking the acl
# And wasting a lot of memory on those user records. it will also
# Force users to authenticate from scratch whenever their ip
# Changes.
# "realm" string
# Specifies the protection scope (aka realm name) which is to be
# Reported to the client for the authentication scheme. it is
# Commonly part of the text the user will see when prompted for
# Their username and password.
# For basic the default is "squid proxy-caching web server".
# For digest there is no default, this parameter is mandatory.
# For ntlm and negotiate this parameter is ignored.
# "children" numberofchildren [startup=n] [idle=n] [concurrency=n]
#        [queue-size=N] [on-persistent-overload=action]
#        [reservation-timeout=seconds]
# The maximum number of authenticator processes to spawn. if
# You start too few squid will have to wait for them to process
# A backlog of credential verifications, slowing it down. when
# Password verifications are done via a (slow) network you are
# Likely to need lots of authenticator processes.
# The startup= and idle= options permit some skew in the exact
# Amount run. a minimum of startup=n will begin during startup
# And reconfigure. squid will start more in groups of up to
# Idle=n in an attempt to meet traffic needs and to keep idle=n
# Free above those traffic needs up to the maximum.
# The concurrency= option sets the number of concurrent requests
# The helper can process.  the default of 0 is used for helpers
# Who only supports one request at a time. setting this to a
# Number greater than 0 changes the protocol used to include a
# Channel id field first on the request/response line, allowing
# Multiple requests to be sent to the same helper in parallel
# Without waiting for the response.
# Concurrency must not be set unless it's known the helper
# Supports the input format with channel-id fields.
# The queue-size option sets the maximum number of queued
# Requests. a request is queued when no existing child can
# Accept it due to concurrency limit and no new child can be
# Started due to numberofchildren limit. the default maximum is
# 2*numberofchildren. squid is allowed to temporarily exceed the
# Configured maximum, marking the affected helper as
#        "overloaded". If the helper overload lasts more than 3
# Minutes, the action prescribed by the on-persistent-overload
# Option applies.
# The on-persistent-overload=action option specifies squid
# Reaction to a new helper request arriving when the helper
# Has been overloaded for more that 3 minutes already. the number
# Of queued requests determines whether the helper is overloaded
#        (see the queue-size option).
# Two actions are supported:
# Die    squid worker quits. this is the default behavior.
# Err    squid treats the helper request as if it was
# Immediately submitted, and the helper immediately
# Replied with an err response. this action has no effect
# On the already queued and in-progress helper requests.
# Note: ntlm and negotiate schemes do not support concurrency
# In the squid code module even though some helpers can.
# The reservation-timeout=seconds option allows ntlm and negotiate
# Helpers to forget about clients that abandon their in-progress
# Connection authentication without closing the connection. the
# Timeout is measured since the last helper response received by
# Squid for the client. fractional seconds are not supported.
# After the timeout, the helper will be used for other clients if
# There are no unreserved helpers available. in the latter case,
# The old client attempt to resume authentication will not be
# Forwarded to the helper (and the client should open a new http
# Connection and retry authentication from scratch).
# By default, reservations do not expire and clients that keep
# Their connections open without completing authentication may
# Exhaust all ntlm and negotiate helpers.
# "keep_alive" on|off
# If you experience problems with put/post requests when using
# The ntlm or negotiate schemes then you can try setting this
# To off. this will cause squid to forcibly close the connection
# On the initial request where the browser asks which schemes
# Are supported by the proxy.
# For basic and digest this parameter is ignored.
# "utf8" on|off
# Useful for sending credentials to authentication backends that
# Expect utf-8 encoding (e.g., ldap).
# When this option is enabled, squid uses http accept-language
# Request header to guess the received credentials encoding
#        (iso-Latin-1, CP1251, or UTF-8) and then converts the first
# Two encodings into utf-8.
# When this option is disabled and by default, squid sends
# Credentials in their original (i.e. received) encoding.
# This parameter is only honored for basic and digest schemes.
# For basic, the entire username:password credentials are
# Checked and, if necessary, re-encoded. for digest -- just the
# Username component. for ntlm and negotiate schemes, this
# Parameter is ignored.
#    === example Configuration ===
# This configuration displays the recommended authentication scheme
# Order from most to least secure with recommended minimum configuration
# Settings for each scheme:
##Auth_param negotiate program <uncomment and complete this line to activate>
##Auth_param negotiate children 20 startup=0 idle=1
##
##Auth_param digest program <uncomment and complete this line to activate>
##Auth_param digest children 20 startup=0 idle=1
##Auth_param digest realm Squid proxy-caching web server
##Auth_param digest nonce_garbage_interval 5 minutes
##Auth_param digest nonce_max_duration 30 minutes
##Auth_param digest nonce_max_count 50
##
##Auth_param ntlm program <uncomment and complete this line to activate>
##Auth_param ntlm children 20 startup=0 idle=1
##
##Auth_param basic program <uncomment and complete this line>
##Auth_param basic children 5 startup=5 idle=1
##Auth_param basic credentialsttl 2 hours
#Default:
# None

# Tag: authenticate_cache_garbage_interval
# The time period between garbage collection across the username cache.
# This is a trade-off between memory utilization (long intervals - say
# 2 days) and cpu (short intervals - say 1 minute). only change if you
# Have good reason to.
#Default:
# Authenticate_cache_garbage_interval 1 hour

# Tag: authenticate_ttl
# The time a user & their credentials stay in the logged in
# User cache since their last request. when the garbage
# Interval passes, all user credentials that have passed their
# Ttl are removed from memory.
#Default:
# Authenticate_ttl 1 hour

# Tag: authenticate_ip_ttl
# If you use proxy authentication and the 'max_user_ip' acl,
# This directive controls how long squid remembers the ip
# Addresses associated with each user.  use a small value
#    (e.g., 60 seconds) if your users might change addresses
# Quickly, as is the case with dialup.   you might be safe
# Using a larger value (e.g., 2 hours) in a corporate lan
# Environment with relatively static address assignments.
#Default:
# Authenticate_ip_ttl 1 second

# Access controls
# -----------------------------------------------------------------------------

# Tag: external_acl_type
# This option defines external acl classes using a helper program
# To look up the status
# External_acl_type name [options] format /path/to/helper [helper arguments]
# Options:
# Ttl=n        ttl in seconds for cached results (defaults to 3600
# For 1 hour)
# Negative_ttl=n
# Ttl for cached negative lookups (default same
# As ttl)
# Grace=n    percentage remaining of ttl where a refresh of a
# Cached entry should be initiated without needing to
# Wait for a new reply. (default is for no grace period)
# Cache=n    the maximum number of entries in the result cache. the
# Default limit is 262144 entries.  each cache entry usually
# Consumes at least 256 bytes. squid currently does not remove
# Expired cache entries until the limit is reached, so a proxy
# Will sooner or later reach the limit. the expanded format
# Value is used as the cache key, so if the details in format
# Are highly variable, a larger cache may be needed to produce
# Reduction in helper load.
# Children-max=n
# Maximum number of acl helper processes spawned to service
# External acl lookups of this type. (default 5)
# Children-startup=n
# Minimum number of acl helper processes to spawn during
# Startup and reconfigure to service external acl lookups
# Of this type. (default 0)
# Children-idle=n
# Number of acl helper processes to keep ahead of traffic
# Loads. squid will spawn this many at once whenever load
# Rises above the capabilities of existing processes.
# Up to the value of children-max. (default 1)
# Concurrency=n    concurrency level per process. only used with helpers
# Capable of processing more than one query at a time.
# Queue-size=n  the queue-size option sets the maximum number of
# Queued requests. a request is queued when no existing
# Helper can accept it due to concurrency limit and no
# New helper can be started due to children-max limit.
# If the queued requests exceed queue size, the acl is
# Ignored. the default value is set to 2*children-max.
# Protocol=2.5    compatibility mode for squid-2.5 external acl helpers.
# Ipv4 / ipv6    ip protocol used to communicate with this helper.
# The default is to auto-detect ipv6 and use it when available.
# Format is a series of %macro codes. see logformat directive for a full list
# Of the accepted codes. although note that at the time of any external acl
# Being tested data may not be available and thus some %macro expand to '-'.
# In addition to the logformat codes; when processing external acls these
# Additional macros are made available:
# %acl        the name of the acl being tested.
# %data        the acl arguments specified in the referencing config
#            'acl ... external' line, separated by spaces (an
#            "argument string"). see acl external.
# If there are no acl arguments %data expands to '-'.
# If you do not specify a data macro inside format,
# Squid automatically appends %data to your format.
# Note that squid-3.x may expand %data to whitespace
# Or nothing in this case.
# By default, squid applies url-encoding to each acl
# Argument inside the argument string. if an explicit
# Encoding modifier is used (e.g., %#data), then squid
# Encodes the whole argument string as a single token
#            (e.g., with %#DATA, spaces between arguments become
#            %20).
# If ssl is enabled, the following formating codes become available:
# %user_cert        ssl user certificate in pem format
#      %user_certchain    SSL User certificate chain in PEM format
#      %user_cert_xx        SSL User certificate subject attribute xx
#      %user_ca_cert_xx    SSL User certificate issuer attribute xx
# Note: all other format codes accepted by older squid versions
# Are deprecated.
# General request syntax:
# [channel-id] format-values
# Format-values consists of transaction details expanded with
# Whitespace separation per the config file format specification
# Using the format macros listed above.
# Request values sent to the helper are url escaped to protect
# Each value in requests against whitespaces.
# If using protocol=2.5 then the request sent to the helper is not
# Url escaped to protect against whitespace.
# Note: protocol=3.0 is deprecated as no longer necessary.
# When using the concurrency= option the protocol is changed by
# Introducing a query channel tag in front of the request/response.
# The query channel tag is a number between 0 and concurrency-1.
# This value must be echoed back unchanged to squid as the first part
# Of the response relating to its request.
# The helper receives lines expanded per the above format specification
# And for each input line returns 1 line starting with ok/err/bh result
# Code and optionally followed by additional keywords with more details.
# General result syntax:
# [channel-id] result keyword=value ...
# Result consists of one of the codes:
# Ok
# The acl test produced a match.
# Err
# The acl test does not produce a match.
# Bh
# An internal error occurred in the helper, preventing
# A result being identified.
# The meaning of 'a match' is determined by your squid.conf
# Access control configuration. see the squid wiki for details.
# Defined keywords:
# User=        the users name (login)
# Password=    the users password (for login= cache_peer option)
# Message=    message describing the reason for this response.
# Available as %o in error pages.
# Useful on (err and bh results).
# Tag=        apply a tag to a request. only sets a tag once,
# Does not alter existing tags.
# Log=        string to be logged in access.log. available as
#            %ea in logformat specifications.
# Clt_conn_tag= associates a tag with the client tcp connection.
# Please see url_rewrite_program related documentation
# For this kv-pair.
# Any keywords may be sent on any response whether ok, err or bh.
# All response keyword values need to be a single token with url
# Escaping, or enclosed in double quotes (") and escaped using \ on
# Any double quotes or \ characters within the value. the wrapping
# Double quotes are removed before the value is interpreted by squid.
#    \r and \n are also replace by CR and LF.
# Some example key values:
# User=john%20smith
# User="john smith"
# User="j. \"bob\" smith"
#Default:
# None

# Tag: acl
# Defining an access list
# Every access list definition must begin with an aclname and acltype,
# Followed by either type-specific arguments or a quoted filename that
# They are read from.
# Acl aclname acltype argument ...
# Acl aclname acltype "file" ...
# When using "file", the file should contain one item per line.
# Acl options
# Some acl types supports options which changes their default behaviour:
# -i,+i    by default, regular expressions are case-sensitive. to make them
# Case-insensitive, use the -i option. to return case-sensitive
# Use the +i option between patterns, or make a new acl line
# Without -i.
# -n    disable lookups and address type conversions.  if lookup or
# Conversion is required because the parameter type (ip or
# Domain name) does not match the message address type (domain
# Name or ip), then the acl would immediately declare a mismatch
# Without any warnings or lookups.
# -m[=delimiters]
# Perform a list membership test, interpreting values as
# Comma-separated token lists and matching against individual
# Tokens instead of whole values.
# The optional "delimiters" parameter specifies one or more
# Alternative non-alphanumeric delimiter characters.
# Non-alphanumeric delimiter characters.
# --    used to stop processing all options, in the case the first acl
# Value has '-' character as first character (for example the '-'
# Is a valid domain name)
# Some acl types require suspending the current request in order
# To access some external data source.
# Those which do are marked with the tag [slow], those which
# Don't are marked as [fast].
# See http://wiki.squid-cache.org/squidfaq/squidacl
# For further information
# ***** acl types available *****
# Acl aclname src ip-address/mask ...    # clients ip address [fast]
# Acl aclname src addr1-addr2/mask ...    # range of addresses [fast]
# Acl aclname dst [-n] ip-address/mask ...    # url host's ip address [slow]
# Acl aclname localip ip-address/mask ... # ip address the client connected to [fast]
#If use_squid_eui
# Acl aclname arp      mac-address ...
# Acl aclname eui64    eui64-address ...
#      # [fast]
#      # Mac (EUI-48) and EUI-64 addresses use xx:xx:xx:xx:xx:xx notation.
#      #
#      # The 'arp' ACL code is not portable to all operating systems.
#      # It works on Linux, Solaris, Windows, FreeBSD, and some other
#      # Bsd variants.
#      #
#      # The eui_lookup directive is required to be 'on' (the default)
#      # And Squid built with --enable-eui for MAC/EUI addresses to be
#      # Available for this ACL.
#      #
#      # Squid can only determine the MAC/EUI address for IPv4
#      # Clients that are on the same subnet. If the client is on a
#      # Different subnet, then Squid cannot find out its address.
#      #
#      # Ipv6 protocol does not contain ARP. MAC/EUI is either
#      # Encoded directly in the IPv6 address or not available.
#Endif
# Acl aclname clientside_mark mark[/mask] ...
#      # Matches CONNMARK of an accepted connection [fast]
#      # Deprecated. Use the 'client_connection_mark' instead.
# Acl aclname client_connection_mark mark[/mask] ...
#      # Matches CONNMARK of an accepted connection [fast]
#      #
#      # Mark and mask are unsigned integers (hex, octal, or decimal).
#      # If multiple marks are given, then the ACL matches if at least
#      # One mark matches.
#      #
#      # Uses netfilter-conntrack library.
#      # Requires building Squid with --enable-linux-netfilter.
#      #
#      # The client, various intermediaries, and Squid itself may set
#      # Connmark at various times. The last CONNMARK set wins. This ACL
#      # Checks the mark present on an accepted connection or set by
#      # Squid afterwards, depending on the ACL check timing. This ACL
#      # Effectively ignores any mark set by other agents after Squid has
#      # Accepted the connection.
# Acl aclname srcdomain   .foo.com ...
#      # Reverse lookup, from client IP [slow]
# Acl aclname dstdomain [-n] .foo.com ...
#      # Destination server from URL [fast]
# Acl aclname srcdom_regex [-i] \.foo\.com ...
#      # Regex matching client name [slow]
# Acl aclname dstdom_regex [-n] [-i] \.foo\.com ...
#      # Regex matching server [fast]
#      #
#      # For dstdomain and dstdom_regex a reverse lookup is tried if a IP
#      # Based URL is used and no match is found. The name "none" is used
#      # If the reverse lookup fails.
# Acl aclname src_as number ...
# Acl aclname dst_as number ...
#      # [fast]
#      # Except for access control, AS numbers can be used for
#      # Routing of requests to specific caches. Here's an
#      # Example for routing all requests for AS#1241 and only
#      # Those to mycache.mydomain.net:
#      # Acl asexample dst_as 1241
#      # Cache_peer_access mycache.mydomain.net allow asexample
#      # Cache_peer_access mycache_mydomain.net deny all
# Acl aclname peername mypeer ...
# Acl aclname peername_regex [-i] regex-pattern ...
#      # [fast]
#      # Match against a named cache_peer entry
#      # Set unique name= on cache_peer lines for reliable use.
# Acl aclname time [day-abbrevs] [h1:m1-h2:m2]
#      # [fast]
#      #  Day-abbrevs:
#      #    S - Sunday
#      #    M - Monday
#      #    T - Tuesday
#      #    W - Wednesday
#      #    H - Thursday
#      #    F - Friday
#      #    A - Saturday
#      #  H1:m1 must be less than h2:m2
# Acl aclname url_regex [-i] ^http:// ...
#      # Regex matching on whole URL [fast]
# Acl aclname urllogin [-i] [^a-za-z0-9] ...
#      # Regex matching on URL login field
# Acl aclname urlpath_regex [-i] \.gif$ ...
#      # Regex matching on URL path [fast]
# Acl aclname port 80 70 21 0-1024...   # destination tcp port [fast]
#                                          # Ranges are alloed
# Acl aclname localport 3128 ...          # tcp port the client connected to [fast]
#                                          # Np: for interception mode this is usually '80'
# Acl aclname myportname 3128 ...       # *_port name [fast]
# Acl aclname proto http ftp ...        # request protocol [fast]
# Acl aclname method get post ...       # http request method [fast]
# Acl aclname http_status 200 301 500- 400-403 ...
#      # Status code in reply [fast]
# Acl aclname browser [-i] regexp ...
#      # Pattern match on User-Agent header (see also req_header below) [fast]
# Acl aclname referer_regex [-i] regexp ...
#      # Pattern match on Referer header [fast]
#      # Referer is highly unreliable, so use with care
# Acl aclname ident [-i] username ...
# Acl aclname ident_regex [-i] pattern ...
#      # String match on ident output [slow]
#      # Use REQUIRED to accept any non-null ident.
# Acl aclname proxy_auth [-i] username ...
# Acl aclname proxy_auth_regex [-i] pattern ...
#      # Perform http authentication challenge to the client and match against
#      # Supplied credentials [slow]
#      #
#      # Takes a list of allowed usernames.
#      # Use REQUIRED to accept any valid username.
#      #
#      # Will use proxy authentication in forward-proxy scenarios, and plain
#      # Http authenticaiton in reverse-proxy scenarios
#      #
#      # Note: when a Proxy-Authentication header is sent but it is not
#      # Needed during ACL checking the username is NOT logged
#      # In access.log.
#      #
#      # Note: proxy_auth requires a EXTERNAL authentication program
#      # To check username/password combinations (see
#      # Auth_param directive).
#      #
#      # Note: proxy_auth can't be used in a transparent/intercepting proxy
#      # As the browser needs to be configured for using a proxy in order
#      # To respond to proxy authentication.
# Acl aclname snmp_community string ...
#      # A community string to limit access to your SNMP Agent [fast]
#      # Example:
#      #
#      #    Acl snmppublic snmp_community public
# Acl aclname maxconn number
#      # This will be matched when the client's IP address has
#      # More than <number> TCP connections established. [fast]
#      # Note: This only measures direct TCP links so X-Forwarded-For
#      # Indirect clients are not counted.
# Acl aclname max_user_ip [-s] number
#      # This will be matched when the user attempts to log in from more
#      # Than <number> different ip addresses. The authenticate_ip_ttl
#      # Parameter controls the timeout on the ip entries. [fast]
#      # If -s is specified the limit is strict, denying browsing
#      # From any further IP addresses until the ttl has expired. Without
#      # -s Squid will just annoy the user by "randomly" denying requests.
#      # (the counter is reset each time the limit is reached and a
#      # Request is denied)
#      # Note: in acceleration mode or where there is mesh of child proxies,
#      # Clients may appear to come from multiple addresses if they are
#      # Going through proxy farms, so a limit of 1 may cause user problems.
# Acl aclname random probability
#      # Pseudo-randomly match requests. Based on the probability given.
#      # Probability may be written as a decimal (0.333), fraction (1/3)
#      # Or ratio of matches:non-matches (3:5).
# Acl aclname req_mime_type [-i] mime-type ...
#      # Regex match against the mime type of the request generated
#      # By the client. Can be used to detect file upload or some
#      # Types HTTP tunneling requests [fast]
#      # Note: This does NOT match the reply. You cannot use this
#      # To match the returned file type.
# Acl aclname req_header header-name [-i] any\.regex\.here
#      # Regex match against any of the known request headers.  May be
#      # Thought of as a superset of "browser", "referer" and "mime-type"
#      # Acl [fast]
# Acl aclname rep_mime_type [-i] mime-type ...
#      # Regex match against the mime type of the reply received by
#      # Squid. Can be used to detect file download or some
#      # Types HTTP tunneling requests. [fast]
#      # Note: This has no effect in http_access rules. It only has
#      # Effect in rules that affect the reply data stream such as
#      # Http_reply_access.
# Acl aclname rep_header header-name [-i] any\.regex\.here
#      # Regex match against any of the known reply headers. May be
#      # Thought of as a superset of "browser", "referer" and "mime-type"
#      # Acls [fast]
# Acl aclname external class_name [arguments...]
#      # External ACL lookup via a helper class defined by the
#      # External_acl_type directive [slow]
# Acl aclname user_cert attribute values...
#      # Match against attributes in a user SSL certificate
#      # Attribute is one of DN/C/O/CN/L/ST or a numerical OID [fast]
# Acl aclname ca_cert attribute values...
#      # Match against attributes a users issuing CA SSL certificate
#      # Attribute is one of DN/C/O/CN/L/ST or a numerical OID  [fast]
# Acl aclname ext_user [-i] username ...
# Acl aclname ext_user_regex [-i] pattern ...
#      # String match on username returned by external acl helper [slow]
#      # Use REQUIRED to accept any non-null user name.
# Acl aclname tag tagvalue ...
#      # String match on tag returned by external acl helper [fast]
#      # Deprecated. Only the first tag will match with this ACL.
#      # Use the 'note' ACL instead for handling multiple tag values.
# Acl aclname hier_code codename ...
#      # String match against squid hierarchy code(s); [fast]
#      #  E.g., DIRECT, PARENT_HIT, NONE, etc.
#      #
#      # Note: This has no effect in http_access rules. It only has
#      # Effect in rules that affect the reply data stream such as
#      # Http_reply_access.
# Acl aclname note [-m[=delimiters]] name [value ...]
#      # Match transaction annotation [fast]
#      # Without values, matches any annotation with a given name.
#      # With value(s), matches any annotation with a given name that
#      # Also has one of the given values.
#      # If the -m flag is used, then the value of the named
#      # Annotation is interpreted as a list of tokens, and the ACL
#      # Matches individual name=token pairs rather than whole
#      # Name=value pairs. See "ACL Options" above for more info.
#      # Annotation sources include note and adaptation_meta directives
#      # As well as helper and eCAP responses.
# Acl aclname annotate_transaction [-m[=delimiters]] key=value ...
# Acl aclname annotate_transaction [-m[=delimiters]] key+=value ...
#      # Always matches. [fast]
#      # Used for its side effect: This ACL immediately adds a
#      # Key=value annotation to the current master transaction.
#      # The added annotation can then be tested using note ACL and
#      # Logged (or sent to helpers) using %note format code.
#      #
#      # Annotations can be specified using replacement and addition
#      # Formats. The key=value form replaces old same-key annotation
#      # Value(s). The key+=value form appends a new value to the old
#      # Same-key annotation. Both forms create a new key=value
#      # Annotation if no same-key annotation exists already. If
#      # -m flag is used, then the value is interpreted as a list
#      # And the annotation will contain key=token pair(s) instead of the
#      # Whole key=value pair.
#      #
#      # This ACL is especially useful for recording complex multi-step
#      # Acl-driven decisions. For example, the following configuration
#      # Avoids logging transactions accepted after aclX matched:
#      #
#      #  # First, mark transactions accepted after aclX matched
#      #  Acl markSpecial annotate_transaction special=true
#      #  Http_access allow acl001
#      #  ...
#      #  Http_access deny acl100
#      #  Http_access allow aclX markSpecial
#      #
#      #  # Second, do not log marked transactions:
#      #  Acl markedSpecial note special true
#      #  Access_log ... deny markedSpecial
#      #
#      #  # Note that the following would not have worked because aclX
#      #  # Alone does not determine whether the transaction was allowed:
#      #  Access_log ... deny aclX # wrong!
#      #
#      # Warning: This ACL annotates the transaction even when negated
#      # And even if subsequent ACLs fail to match. For example, the
#      # Following three rules will have exactly the same effect as far
#      # As annotations set by the "mark" ACL are concerned:
#      #
#      #  Some_directive acl1 ... mark # rule matches if mark is reached
#      #  Some_directive acl1 ... !mark     # rule never matches
#      #  Some_directive acl1 ... mark !all # rule never matches
# Acl aclname annotate_client [-m[=delimiters]] key=value ...
# Acl aclname annotate_client [-m[=delimiters]] key+=value ...
#      #
#      # Always matches. [fast]
#      # Used for its side effect: This ACL immediately adds a
#      # Key=value annotation to the current client-to-Squid
#      # Connection. Connection annotations are propagated to the current
#      # And all future master transactions on the annotated connection.
#      # See the annotate_transaction ACL for details.
#      #
#      # For example, the following configuration avoids rewriting URLs
#      # Of transactions bumped by SslBump:
#      #
#      #  # First, mark bumped connections:
#      #  Acl markBumped annotate_client bumped=true
#      #  Ssl_bump peek acl1
#      #  Ssl_bump stare acl2
#      #  Ssl_bump bump acl3 markBumped
#      #  Ssl_bump splice all
#      #
#      #  # Second, do not send marked transactions to the redirector:
#      #  Acl markedBumped note bumped true
#      #  Url_rewrite_access deny markedBumped
#      #
#      #  # Note that the following would not have worked because acl3 alone
#      #  # Does not determine whether the connection is going to be bumped:
#      #  Url_rewrite_access deny acl3 # wrong!
# Acl aclname adaptation_service service ...
#      # Matches the name of any icap_service, ecap_service,
#      # Adaptation_service_set, or adaptation_service_chain that Squid
#      # Has used (or attempted to use) for the master transaction.
#      # This ACL must be defined after the corresponding adaptation
#      # Service is named in squid.conf. This ACL is usable with
#      # Adaptation_meta because it starts matching immediately after
#      # The service has been selected for adaptation.
# Acl aclname transaction_initiator initiator ...
#      # Matches transaction's initiator [fast]
#      #
#      # Supported initiators are:
#      #  Esi: matches transactions fetching ESI resources
#      #  Certificate-fetching: matches transactions fetching
#      #     A missing intermediate TLS certificate
#      #  Cache-digest: matches transactions fetching Cache Digests
#      #     From a cache_peer
#      #  Htcp: matches HTCP requests from peers
#      #  Icp: matches ICP requests to peers
#      #  Icmp: matches ICMP RTT database (NetDB) requests to peers
#      #  Asn: matches asns db requests
#      #  Internal: matches any of the above
#      #  Client: matches transactions containing an HTTP or FTP
#      #     Client request received at a Squid *_port
#      #  All: matches any transaction, including internal transactions
#      #     Without a configurable initiator and hopefully rare
#      #     Transactions without a known-to-Squid initiator
#      #
#      # Multiple initiators are ORed.
# Acl aclname has component
#      # Matches a transaction "component" [fast]
#      #
#      # Supported transaction components are:
#      #  Request: transaction has a request header (at least)
#      #  Response: transaction has a response header (at least)
#      #  Ale: transaction has an internally-generated Access Log Entry
#      #       Structure; bugs notwithstanding, all transaction have it
#      #
#      # For example, the following configuration helps when dealing with HTTP
#      # Clients that close connections without sending a request header:
#      #
#      #  Acl hasRequest has request
#      #  Acl logMe note important_transaction
#      #  # Avoid "logMe ACL is used in context without an HTTP request" warnings
#      #  Access_log ... logformat=detailed hasRequest logMe
#      #  # Log request-less transactions, instead of ignoring them
#      #  Access_log ... logformat=brief !hasRequest
#      #
#      # Multiple components are not supported for one "acl" rule, but
#      # Can be specified (and are ORed) using multiple same-name rules:
#      #
#      #  # Ok, this strange logging daemon needs request or response,
#      #  # But can work without either a request or a response:
#      #  Acl hasWhatMyLoggingDaemonNeeds has request
#      #  Acl hasWhatMyLoggingDaemonNeeds has response
#Acl aclname at_step step
#      # Match against the current request processing step [fast]
#      # Valid steps are:
#      #   Generatingconnect: Generating HTTP CONNECT request headers
# Acl aclname any-of acl1 acl2 ...
#      # Match any one of the acls [fast or slow]
#      # The first matching ACL stops further ACL evaluation.
#      #
#      # Acls from multiple any-of lines with the same name are ORed.
#      # For example, A = (a1 or a2) or (a3 or a4) can be written as
#      #   Acl A any-of a1 a2
#      #   Acl A any-of a3 a4
#      #
#      # This group ACL is fast if all evaluated ACLs in the group are fast
#      # And slow otherwise.
# Acl aclname all-of acl1 acl2 ...
#      # Match all of the acls [fast or slow]
#      # The first mismatching ACL stops further ACL evaluation.
#      #
#      # Acls from multiple all-of lines with the same name are ORed.
#      # For example, B = (b1 and b2) or (b3 and b4) can be written as
#      #   Acl B all-of b1 b2
#      #   Acl B all-of b3 b4
#      #
#      # This group ACL is fast if all evaluated ACLs in the group are fast
#      # And slow otherwise.
# Examples:
# Acl macaddress arp 09:00:2b:23:45:67
# Acl myexample dst_as 1241
# Acl password proxy_auth required
# Acl fileupload req_mime_type -i ^multipart/form-data$
# Acl javascript rep_mime_type -i ^application/x-javascript$
#Default:
# Acls all, manager, localhost, to_localhost, and connect are predefined.
# Recommended minimum configuration:

# Example rule allowing access from your local networks.
# Adapt to list your (internal) ip networks from where browsing should be allowed.

acl localnet src 172.16.0.0/12                  # Rfc 1918 local private network [LAN]
acl localnet src 192.168.0.0/16                 # Rfc 1918 local private network [LAN]

acl SSL_ports port 443

acl Safe_ports port 80                          # Http
acl Safe_ports port 21                          # Ftp
acl Safe_ports port 443                         # Https
acl Safe_ports port 70                          # Gopher
acl Safe_ports port 210                         # Wais
acl Safe_ports port 1025-65535                  # Unregistered ports
acl Safe_ports port 280                         # Http-mgmt
acl Safe_ports port 488                         # Gss-http
acl Safe_ports port 563                         # Commonly used (at least at one time) for NNTP (USENET news transfer) over SSL
acl Safe_ports port 591                         # Filemaker
acl Safe_ports port 777                         # Multiling http
acl whitelist dstdomain $squid_whitelist
acl blacklist dstdomain squid_blacklist

# Set all connections in the following ip range to allow access to squid's cache

# Tag: proxy_protocol_access
# Determine which client proxies can be trusted to provide correct
# Information regarding real client ip address using proxy protocol.
# Requests may pass through a chain of several other proxies
# Before reaching us. the original source details may by sent in:
#        * http message Forwarded header, or
#        * http message X-Forwarded-For header, or
#        * proxy protocol connection header.
# This directive is solely for validating new proxy protocol
# Connections received from a port flagged with require-proxy-header.
# It is checked only once after tcp connection setup.
# A deny match results in tcp connection closure.
# An allow match is required for squid to permit the corresponding
# Tcp connection, before squid even looks for http request headers.
# If there is an allow match, squid starts using proxy header information
# To determine the source address of the connection for all future acl
# Checks, logging, etc.
# Security considerations:
# Any host from which we accept client ip details can place
# Incorrect information in the relevant header, and squid
# Will use the incorrect information as if it were the
# Source address of the request.  this may enable remote
# Hosts to bypass any access control restrictions that are
# Based on the client's source addresses.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# All tcp connections to ports with require-proxy-header will be denied

# Tag: follow_x_forwarded_for
# Determine which client proxies can be trusted to provide correct
# Information regarding real client ip address.
# Requests may pass through a chain of several other proxies
# Before reaching us. the original source details may by sent in:
#        * http message Forwarded header, or
#        * http message X-Forwarded-For header, or
#        * proxy protocol connection header.
# Proxy protocol connections are controlled by the proxy_protocol_access
# Directive which is checked before this.
# If a request reaches us from a source that is allowed by this
# Directive, then we trust the information it provides regarding
# The ip of the client it received from (if any).
# For the purpose of acls used in this directive the src acl type always
# Matches the address we are testing and srcdomain matches its rdns.
# On each http request squid checks for x-forwarded-for header fields.
# If found the header values are iterated in reverse order and an allow
# Match is required for squid to continue on to the next value.
# The verification ends when a value receives a deny match, cannot be
# Tested, or there are no more values to test.
# Note: squid does not yet follow the forwarded http header.
# The end result of this process is an ip address that we will
# Refer to as the indirect client address.  this address may
# Be treated as the client address for access control, icap, delay
# Pools and logging, depending on the acl_uses_indirect_client,
# Icap_uses_indirect_client, delay_pool_uses_indirect_client,
# Log_uses_indirect_client and tproxy_uses_indirect_client options.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# Security considerations:
# Any host from which we accept client ip details can place
# Incorrect information in the relevant header, and squid
# Will use the incorrect information as if it were the
# Source address of the request.  this may enable remote
# Hosts to bypass any access control restrictions that are
# Based on the client's source addresses.
# For example:
# Acl localhost src 127.0.0.1
# Acl my_other_proxy srcdomain .proxy.example.com
# Follow_x_forwarded_for allow localhost
# Follow_x_forwarded_for allow my_other_proxy
#Default:
# X-forwarded-for header will be ignored.

# Tag: acl_uses_indirect_client    on|off
# Controls whether the indirect client address
#    (see follow_x_forwarded_for) is used instead of the
# Direct client address in acl matching.
# Note: maxconn acl considers direct tcp links and indirect
# Clients will always have zero. so no match.
#Default:
# Acl_uses_indirect_client on

# Tag: delay_pool_uses_indirect_client    on|off
# Controls whether the indirect client address
#    (see follow_x_forwarded_for) is used instead of the
# Direct client address in delay pools.
#Default:
# Delay_pool_uses_indirect_client on

# Tag: log_uses_indirect_client    on|off
# Controls whether the indirect client address
#    (see follow_x_forwarded_for) is used instead of the
# Direct client address in the access log.
#Default:
# Log_uses_indirect_client on

# Tag: tproxy_uses_indirect_client    on|off
# Controls whether the indirect client address
#    (see follow_x_forwarded_for) is used instead of the
# Direct client address when spoofing the outgoing client.
# This has no effect on requests arriving in non-tproxy
# Mode ports.
# Security warning: usage of this option is dangerous
# And should not be used trivially. correct configuration
# Of follow_x_forwarded_for with a limited set of trusted
# Sources is required to prevent abuse of your proxy.
#Default:
# Tproxy_uses_indirect_client off

# Tag: spoof_client_ip
# Control client ip address spoofing of tproxy traffic based on
# Defined access lists.
# Spoof_client_ip allow|deny [!]aclname ...
# If there are no "spoof_client_ip" lines present, the default
# Is to "allow" spoofing of any suitable request.
# Note that the cache_peer "no-tproxy" option overrides this acl.
# This clause supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Allow spoofing on all tproxy traffic.

# Tag: http_access
# Allowing or denying access based on defined access lists
# To allow or deny a message received on an http, https, or ftp port:
# Http_access allow|deny [!]aclname ...
# Note on default values:
# If there are no "access" lines present, the default is to deny
# The request.
# If none of the "access" lines cause a match, the default is the
# Opposite of the last line in the list.  if the last line was
# Deny, the default is allow.  conversely, if the last line
# Is allow, the default will be deny.  for these reasons, it is a
# Good idea to have an "deny all" entry at the end of your access
# Lists to avoid potential confusion.
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Deny, unless rules exist in squid.conf.

# Recommended minimum access permission configuration:
# Deny requests to certain unsafe ports
http_access deny !Safe_ports

# Allow connect to other than secure ssl ports
http_access allow !SSL_ports

# Only allow cachemgr access from localhost
http_access allow localhost manager
http_access deny manager

# We strongly recommend the following be uncommented to protect innocent
# Web applications running on the proxy server who think the only
# One who can access services on "localhost" is a local user
http_access deny to_localhost

# Insert your own rule(s) here to allow access from your clients
include /etc/squid/conf.d/*

##
##
##############################
## Start OF CUSTOM COMMANDS ##
##############################
##
##

include /etc/squid/conf.d/*
auth_param basic program $basic_ncsa_auth $squid_passwords
auth_param basic realm proxy
auth_param basic children 5
acl authenticated proxy_auth REQUIRED
acl github dstdomain .github.com
cache deny github

# Adapt localnet in the acl section to list your (internal) ip networks from where browsing should be allowed
http_access deny !authenticated
http_access allow localnet
http_access allow localhost
http_access allow whitelist

# And finally deny all other access to this proxy
http_access deny blacklist
http_access deny all

# This specifies the maximum buffer size of a client request.
# It prevents squid eating too much memory when somebody uploads a large file.
client_request_buffer_max_size $client_rqst_bfr_size

# Set dns nameserver addresses
dns_nameservers $dns_server_ip

# Set the file size range the proxy will actively cache
minimum_object_size $min_obj_size
maximum_object_size $max_obj_size
maximum_object_size_in_memory $max_obj_size_mem

cache_swap_low $cache_swp_low
cache_swap_high $cache_swp_high

# Always: keep most recently fetched objects in memory (default)
memory_cache_mode $mem_cache_mode

# Uncomment and adjust the following to add a disk cache directory.
cache_dir ufs $cache_dir_squid $cache_dir_squid_size 16 256

########################################
## Your custom refresh_patterns below ##
########################################
refresh_pattern \/master$                                    0         0%        0  refresh-ims
####################################
## Default refresh_patterns below ##
####################################
refresh_pattern ^ftp:                                     1440        20%    10080
refresh_pattern ^gopher:                                  1440         0%     1440
refresh_pattern -i (/cgi-bin/|\?)                            0         0%        0
refresh_pattern \/(Packages|Sources)(|\.bz2|\.gz|\.xz)$      0         0%        0  refresh-ims
refresh_pattern \/Release(|\.gpg)$                           0         0%        0  refresh-ims
refresh_pattern \/InRelease$                                 0         0%        0  refresh-ims
refresh_pattern \/(Translation-.*)(|\.bz2|\.gz|\.xz)$        0         0%        0  refresh-ims
# Example pattern for deb packages
refresh_pattern (\.deb|\.udeb)$                         129600       100%   129600
refresh_pattern .                                            0        20%     4320

# Cache memory transit file allocation max size limit
cache_mem $cache_mem

# Set default squid proxy port
http_port 3128

# Set visible hostname
visible_hostname $hostname

# Some servers incorrectly signal the use of http/1.0 persistent connections including on replies
# Not compatible, causing significant delays. mostly happens on redirects. enabling attempts to
# Detect broken replies and automatically assumes the reply is finished after a 10 second timeout.
detect_broken_pconn $detect_broken_pconn
client_persistent_connections $client_pcons
server_persistent_connections $server_pcons

# Set default user/owner for squid
cache_effective_user $squid_user

http_accel_surrogate_remote on
esi_parser expat

# Set how long squid waits during shutdown, default is 30 seconds
shutdown_lifetime $sd_tout

##
############################
## End OF CUSTOM COMMANDS ##
############################
##

# Tag: adapted_http_access
# Allowing or denying access based on defined access lists
# Essentially identical to http_access, but runs after redirectors
# And icap/ecap adaptation. allowing access control based on their
# Output.
# If not set then only http_access is used.
#Default:
# Allow, unless rules exist in squid.conf.

# Tag: http_reply_access
# Allow replies to client requests. this is complementary to http_access.
# Http_reply_access allow|deny [!] aclname ...
# Note: if there are no access lines present, the default is to allow
# All replies.
# If none of the access lines cause a match the opposite of the
# Last line will apply. thus it is good practice to end the rules
# With an "allow all" or "deny all" entry.
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Allow, unless rules exist in squid.conf.

# Tag: icp_access
# Allowing or denying access to the icp port based on defined
# Access lists
# Icp_access  allow|deny [!]aclname ...
# Note: the default if no icp_access lines are present is to
# Deny all traffic. this default may cause problems with peers
# Using icp.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
## Allow ICP queries from local networks only
##Icp_access allow localnet
##Icp_access deny all
#Default:
# Deny, unless rules exist in squid.conf.

# Tag: htcp_access
# Allowing or denying access to the htcp port based on defined
# Access lists
# Htcp_access  allow|deny [!]aclname ...
# See also htcp_clr_access for details on access control for
# Cache purge (clr) htcp messages.
# Note: the default if no htcp_access lines are present is to
# Deny all traffic. this default may cause problems with peers
# Using the htcp option.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
## Allow HTCP queries from local networks only
##Htcp_access allow localnet
##Htcp_access deny all
#Default:
# Deny, unless rules exist in squid.conf.

# Tag: htcp_clr_access
# Allowing or denying access to purge content using htcp based
# On defined access lists.
# See htcp_access for details on general htcp access control.
# Htcp_clr_access  allow|deny [!]aclname ...
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
## Allow HTCP CLR requests from trusted peers
#Acl htcp_clr_peer src 192.0.2.2 2001:DB8::2
#Htcp_clr_access allow htcp_clr_peer
#Htcp_clr_access deny all
#Default:
# Deny, unless rules exist in squid.conf.

# Tag: miss_access
# Determines whether network access is permitted when satisfying a request.
# For example;
# To force your neighbors to use you as a sibling instead of
# A parent.
# Acl localclients src 192.0.2.0/24 2001:db8::a:0/64
# Miss_access deny  !localclients
# Miss_access allow all
# This means only your local clients are allowed to fetch relayed/miss
# Replies from the network and all other clients can only fetch cached
# Objects (hits).
# The default for this setting allows all clients who passed the
# Http_access rules to relay via this proxy.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Allow, unless rules exist in squid.conf.

# Tag: ident_lookup_access
# A list of acl elements which, if matched, cause an ident
#    (rfc 931) lookup to be performed for this request.  For
# Example, you might choose to always perform ident lookups
# For your main multi-user unix boxes, but not for your macs
# And pcs.  by default, ident lookups are not performed for
# Any requests.
# To enable ident lookups for specific client addresses, you
# Can follow this example:
# Acl ident_aware_hosts src 198.168.1.0/24
# Ident_lookup_access allow ident_aware_hosts
# Ident_lookup_access deny all
# Only src type acl checks are fully supported.  a srcdomain
# Acl might work at times, but it will not always provide
# The correct result.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Unless rules exist in squid.conf, ident is not fetched.

# Tag: reply_body_max_size    size [acl acl...]
# This option specifies the maximum size of a reply body. it can be
# Used to prevent users from downloading very large files, such as
# Mp3's and movies. when the reply headers are received, the
# Reply_body_max_size lines are processed, and the first line where
# All (if any) listed acls are true is used as the maximum body size
# For this reply.
# This size is checked twice. first when we get the reply headers,
# We check the content-length value.  if the content length value exists
# And is larger than the allowed size, the request is denied and the
# User receives an error message that says "the request or reply
# Is too large." if there is no content-length, and the reply
# Size exceeds this limit, the client's connection is just closed
# And they will receive a partial reply.
# Warning: downstream caches probably can not detect a partial reply
# If there is no content-length header, so they will cache
# Partial responses and give them out as hits.  you should not
# Use this option if you have downstream caches.
# Warning: a maximum size smaller than the size of squid's error messages
# Will cause an infinite loop and crash squid. ensure that the smallest
# Non-zero value you use is greater that the maximum header size plus
# The size of your largest error page.
# If you set this parameter none (the default), there will be
# No limit imposed.
# Configuration format is:
# Reply_body_max_size size units [acl ...]
# Ie.
# Reply_body_max_size 10 mb
#Default:
# No limit is applied.

# Tag: on_unsupported_protocol
# Determines squid behavior when encountering strange requests at the
# Beginning of an accepted tcp connection or the beginning of a bumped
# Connect tunnel. controlling squid reaction to unexpected traffic is
# Especially useful in interception environments where squid is likely
# To see connections for unsupported protocols that squid should either
# Terminate or tunnel at tcp level.
# On_unsupported_protocol <action> [!]acl ...
# The first matching action wins. only fast acls are supported.
# Supported actions are:
# Tunnel: establish a tcp connection with the intended server and
# Blindly shovel tcp packets between the client and server.
# Respond: respond with an error message, using the transfer protocol
# For the squid port that received the request (e.g., http
# For connections intercepted at the http_port). this is the
# Default.
# Squid expects the following traffic patterns:
# Http_port: a plain http request
# Https_port: ssl/tls handshake followed by an [encrypted] http request
# Ftp_port: a plain ftp command (no on_unsupported_protocol support yet!)
# Connect tunnel on http_port: same as https_port
# Connect tunnel on https_port: same as https_port
# Currently, this directive has effect on intercepted connections and
# Bumped tunnels only. other cases are not supported because squid
# Cannot know the intended destination of other traffic.
# For example:
#      # Define what Squid errors indicate receiving non-HTTP traffic:
# Acl foreignprotocol squid_error err_protocol_unknown err_too_big
#      # Define what Squid errors indicate receiving nothing:
# Acl servertalksfirstprotocol squid_error err_request_start_timeout
#      # Tunnel everything that does not look like HTTP:
# On_unsupported_protocol tunnel foreignprotocol
#      # Tunnel if we think the client waits for the server to talk first:
# On_unsupported_protocol tunnel servertalksfirstprotocol
#      # In all other error cases, just send an HTTP "error page" response:
# On_unsupported_protocol respond all
# See also: squid_error acl
#Default:
# Respond with an error message to unidentifiable traffic

# Tag: auth_schemes
# Use this directive to customize authentication schemes presence and
# Order in squid's unauthorized and authentication required responses.
# Auth_schemes scheme1,scheme2,... [!]aclname ...
# Where schemen is the name of one of the authentication schemes
# Configured using auth_param directives. at least one scheme name is
# Required. multiple scheme names are separated by commas. either
# Avoid whitespace or quote the entire schemes list.
# A special "all" scheme name expands to all auth_param-configured
# Schemes in their configuration order. this directive cannot be used
# To configure squid to offer no authentication schemes at all.
# The first matching auth_schemes rule determines the schemes order
# For the current authentication required transaction. note that the
# Future response is not yet available during auth_schemes evaluation.
# If this directive is not used or none of its rules match, then squid
# Responds with all configured authentication schemes in the order of
# Auth_param directives in the configuration file.
# This directive does not determine when authentication is used or
# How each authentication scheme authenticates clients.
# The following example sends basic and negotiate authentication
# Schemes, in that order, when requesting authentication of http
# Requests matching the isie acl (not shown) while sending all
# Auth_param schemes in their configuration order to other clients:
# Auth_schemes basic,negotiate isie
# Auth_schemes all all # explicit default
# This directive supports fast acls only.
# See also: auth_param.
#Default:
# Use all auth_param schemes in their configuration order

# Network options
# -----------------------------------------------------------------------------

# Tag: http_port
# Usage:    port [mode] [options]
# Hostname:port [mode] [options]
# 1.2.3.4:port [mode] [options]
# The socket addresses where squid will listen for http client
# Requests.  you may specify multiple socket addresses.
# There are three forms: port alone, hostname with port, and
# Ip address with port.  if you specify a hostname or ip
# Address, squid binds the socket to that specific
# Address. most likely, you do not need to bind to a specific
# Address, so you can use the port number alone.
# If you are running squid in accelerator mode, you
# Probably want to listen on port 80 also, or instead.
# The -a command line option may be used to specify additional
# Port(s) where squid listens for proxy request. such ports will
# Be plain proxy ports with no options.
# You may specify multiple socket addresses on multiple lines.
# Modes:
# Intercept    support for ip-layer nat interception delivering
# Traffic to this squid port.
# Np: disables authentication on the port.
# Tproxy    support linux tproxy (or bsd divert-to) with spoofing
# Of outgoing connections using the client ip address.
# Np: disables authentication on the port.
# Accel    accelerator / reverse proxy mode
# Ssl-bump    for each connect request allowed by ssl_bump acls,
# Establish secure connection with the client and with
# The server, decrypt https messages as they pass through
# Squid, and treat them as unencrypted http messages,
# Becoming the man-in-the-middle.
# The ssl_bump option is required to fully enable
# Bumping of connect requests.
# Omitting the mode flag causes default forward proxy mode to be used.
# Accelerator mode options:
# Defaultsite=domainname
# What to use for the host: header if it is not present
# In a request. determines what site (not origin server)
# Accelerators should consider the default.
# No-vhost    disable using http/1.1 host header for virtual domain support.
# Protocol=    protocol to reconstruct accelerated and intercepted
# Requests with. defaults to http/1.1 for http_port and
# Https/1.1 for https_port.
# When an unsupported value is configured squid will
# Produce a fatal error.
# Values: http or http/1.1, https or https/1.1
# Vport    virtual host port support. using the http_port number
# Instead of the port passed on host: headers.
# Vport=nn    virtual host port support. using the specified port
# Number instead of the port passed on host: headers.
# Act-as-origin
# Act as if this squid is the origin server.
# This currently means generate new date: and expires:
# Headers on hit instead of adding age:.
# Ignore-cc    ignore request cache-control headers.
# Warning: this option violates http specifications if
# Used in non-accelerator setups.
# Allow-direct    allow direct forwarding in accelerator mode. normally
# Accelerated requests are denied direct forwarding as if
# Never_direct was used.
# Warning: this option opens accelerator mode to security
# Vulnerabilities usually only affecting in interception
# Mode. make sure to protect forwarding with suitable
# Http_access rules when using this.
# Ssl bump mode options:
# In addition to these options ssl-bump requires tls/ssl options.
# Generate-host-certificates[=<on|off>]
# Dynamically create ssl server certificates for the
# Destination hosts of bumped connect requests.when
# Enabled, the cert and key options are used to sign
# Generated certificates. otherwise generated
# Certificate will be selfsigned.
# If there is a ca certificate lifetime of the generated
# Certificate equals lifetime of the ca certificate. if
# Generated certificate is selfsigned lifetime is three
# Years.
# This option is enabled by default when ssl-bump is used.
# See the ssl-bump option above for more information.
# Dynamic_cert_mem_cache_size=size
# Approximate total ram size spent on cached generated
# Certificates. if set to zero, caching is disabled. the
# Default value is 4mb.
# Tls / ssl options:
# Tls-cert=    path to file containing an x.509 certificate (pem format)
# To be used in the tls handshake serverhello.
# If this certificate is constrained by keyusage tls
# Feature it must allow http server usage, along with
# Any additional restrictions imposed by your choice
# Of options= settings.
# When openssl is used this file may also contain a
# Chain of intermediate ca certificates to send in the
# Tls handshake.
# When gnutls is used this option (and any paired
# Tls-key= option) may be repeated to load multiple
# Certificates for different domains.
# Also, when generate-host-certificates=on is configured
# The first tls-cert= option must be a ca certificate
# Capable of signing the automatically generated
# Certificates.
# Tls-key=    path to a file containing private key file (pem format)
# For the previous tls-cert= option.
# If tls-key= is not specified tls-cert= is assumed to
# Reference a pem file containing both the certificate
# And private key.
# Cipher=    colon separated list of supported ciphers.
# Note: some ciphers such as edh ciphers depend on
# Additional settings. if those settings are
# Omitted the ciphers may be silently ignored
# By the openssl library.
# Options=    various ssl implementation options. the most important
# Being:
# No_sslv3    disallow the use of sslv3
# No_tlsv1    disallow the use of tlsv1.0
# No_tlsv1_1  disallow the use of tlsv1.1
# No_tlsv1_2  disallow the use of tlsv1.2
# Single_dh_use
# Always create a new key when using
# Temporary/ephemeral dh key exchanges
# Single_ecdh_use
# Enable ephemeral ecdh key exchange.
# The adopted curve should be specified
# Using the tls-dh option.
# No_ticket
# Disable use of rfc5077 session tickets.
# Some servers may have problems
# Understanding the tls extension due
# To ambiguous specification in rfc4507.
# All       enable various bug workarounds
# Suggested as "harmless" by openssl
# Be warned that this reduces ssl/tls
# Strength to some attacks.
# See the openssl ssl_ctx_set_options documentation for a
# More complete list.
# Clientca=    file containing the list of cas to use when
# Requesting a client certificate.
# Tls-cafile=    pem file containing ca certificates to use when verifying
# Client certificates. if not configured clientca will be
# Used. may be repeated to load multiple files.
# Capath=    directory containing additional ca certificates
# And crl lists to use when verifying client certificates.
# Requires openssl or libressl.
# Crlfile=    file of additional crl lists to use when verifying
# The client certificate, in addition to crls stored in
# The capath. implies verify_crl flag below.
# Tls-dh=[curve:]file
# File containing dh parameters for temporary/ephemeral dh key
# Exchanges, optionally prefixed by a curve for ephemeral ecdh
# Key exchanges.
# See openssl documentation for details on how to create the
# Dh parameter file. supported curves for ecdh can be listed
# Using the "openssl ecparam -list_curves" command.
# Warning: edh and eecdh ciphers will be silently disabled if
# This option is not set.
# Sslflags=    various flags modifying the use of ssl:
# Delayed_auth
# Don't request client certificates
# Immediately, but wait until acl processing
# Requires a certificate (not yet implemented).
# Conditional_auth
# Request a client certificate during the tls
# Handshake, but ignore certificate absence in
# The tls client hello. if the client does
# Supply a certificate, it is validated.
# No_session_reuse
# Don't allow for session reuse. each connection
# Will result in a new ssl session.
# Verify_crl
# Verify crl lists when accepting client
# Certificates.
# Verify_crl_all
# Verify crl lists for all certificates in the
# Client certificate chain.
# Tls-default-ca[=off]
# Whether to use the system trusted cas. default is off.
# Tls-no-npn    do not use the tls npn extension to advertise http/1.1.
# Sslcontext=    ssl session id context identifier.
# Other options:
# Connection-auth[=on|off]
# Use connection-auth=off to tell squid to prevent
# Forwarding microsoft connection oriented authentication
#            (ntlm, Negotiate and Kerberos)
# Disable-pmtu-discovery=
# Control path-mtu discovery usage:
# Off        lets os decide on what to do (default).
# Transparent    disable pmtu discovery when transparent
# Support is enabled.
# Always    disable always pmtu discovery.
# In many setups of transparently intercepting proxies
# Path-mtu discovery can not work on traffic towards the
# Clients. this is the case when the intercepting device
# Does not fully track connections and fails to forward
# Icmp must fragment messages to the cache server. if you
# Have such setup and experience that certain clients
# Sporadically hang or never complete requests set
# Disable-pmtu-discovery option to 'transparent'.
# Name=    specifies a internal name for the port. defaults to
# The port specification (port or addr:port)
# Tcpkeepalive[=idle,interval,timeout]
# Enable tcp keepalive probes of idle connections.
# In seconds; idle is the initial time before tcp starts
# Probing the connection, interval how often to probe, and
# Timeout the time before giving up.
# Require-proxy-header
# Require proxy protocol version 1 or 2 connections.
# The proxy_protocol_access is required to permit
# Downstream proxies which can be trusted.
# Worker-queues
# Ask tcp stack to maintain a dedicated listening queue
# For each worker accepting requests at this port.
# Requires tcp stack that supports the so_reuseport socket
# Option.
# Security warning: enabling worker-specific queues
# Allows any process running as squid's effective user to
# Easily accept requests destined to this port.
# If you run squid on a dual-homed machine with an internal
# And an external interface we recommend you to specify the
# Internal address:port in http_port. this way squid will only be
# Visible on the internal address.

# Squid normally listens to port 3128

# Tag: https_port
# Usage:  [ip:]port [mode] tls-cert=certificate.pem [options]
# The socket address where squid will listen for client requests made
# Over tls or ssl connections. commonly referred to as https.
# This is most useful for situations where you are running squid in
# Accelerator mode and you want to do the tls work at the accelerator
# Level.
# You may specify multiple socket addresses on multiple lines,
# Each with their own certificate and/or options.
# The tls-cert= option is mandatory on https ports.
# See http_port for a list of modes and options.
#Default:
# None

# Tag: ftp_port
# Enables native ftp proxy by specifying the socket address where squid
# Listens for ftp client requests. see http_port directive for various
# Ways to specify the listening address and mode.
# Usage: ftp_port address [mode] [options]
# Warning: this is a new, experimental, complex feature that has seen
# Limited production exposure. some squid modules (e.g., caching) do not
# Currently work with native ftp proxying, and many features have not
# Even been tested for compatibility. test well before deploying!
# Native ftp proxying differs substantially from proxying http requests
# With ftp:// uris because squid works as an ftp server and receives
# Actual ftp commands (rather than http requests with ftp urls).
# Native ftp commands accepted at ftp_port are internally converted or
# Wrapped into http-like messages. the same happens to native ftp
# Responses received from ftp origin servers. those http-like messages
# Are shoveled through regular access control and adaptation layers
# Between the ftp client and the ftp origin server. this allows squid to
# Examine, adapt, block, and log ftp exchanges. squid reuses most http
# Mechanisms when shoveling wrapped ftp messages. for example,
# Http_access and adaptation_access directives are used.
# Modes:
# Intercept    same as http_port intercept. the ftp origin address is
# Determined based on the intended destination of the
# Intercepted connection.
# Tproxy    support linux tproxy for spoofing outgoing
# Connections using the client ip address.
# Np: disables authentication and maybe ipv6 on the port.
# By default (i.e., without an explicit mode option), squid extracts the
# Ftp origin address from the login@origin parameter of the ftp user
# Command. many popular ftp clients support such native ftp proxying.
# Options:
# Name=token    specifies an internal name for the port. defaults to
# The port address. usable with myportname acl.
# Ftp-track-dirs
# Enables tracking of ftp directories by injecting extra
# Pwd commands and adjusting request-uri (in wrapping
# Http requests) to reflect the current ftp server
# Directory. tracking is disabled by default.
# Protocol=ftp    protocol to reconstruct accelerated and intercepted
# Requests with. defaults to ftp. no other accepted
# Values have been tested with. an unsupported value
# Results in a fatal error. accepted values are ftp,
# Http (or http/1.1), and https (or https/1.1).
# Other http_port modes and options that are not specific to http and
# Https may also work.
#Default:
# None

# Tag: tcp_outgoing_tos
# Allows you to select a tos/diffserv value for packets outgoing
# On the server side, based on an acl.
# Tcp_outgoing_tos ds-field [!]aclname ...
# Example where normal_service_net uses the tos value 0x00
# And good_service_net uses 0x20
# Acl normal_service_net src 10.0.0.0/24
# Acl good_service_net src 10.0.1.0/24
# Tcp_outgoing_tos 0x00 normal_service_net
# Tcp_outgoing_tos 0x20 good_service_net
# Tos/dscp values really only have local significance - so you should
# Know what you're specifying. for more information, see rfc2474,
# Rfc2475, and rfc3260.
# The tos/dscp byte must be exactly that - a octet value  0 - 255, or
#    "default" to use whatever default your host has.
# Note that only multiples of 4 are usable as the two rightmost bits have
# Been redefined for use by ecn (rfc 3168 section 23.1).
# The squid parser will enforce this by masking away the ecn bits.
# Processing proceeds in the order specified, and stops at first fully
# Matching line.
# Only fast acls are supported.
#Default:
# None

# Tag: clientside_tos
# Allows you to select a tos/dscp value for packets being transmitted
# On the client-side, based on an acl.
# Clientside_tos ds-field [!]aclname ...
# Example where normal_service_net uses the tos value 0x00
# And good_service_net uses 0x20
# Acl normal_service_net src 10.0.0.0/24
# Acl good_service_net src 10.0.1.0/24
# Clientside_tos 0x00 normal_service_net
# Clientside_tos 0x20 good_service_net
# Note: this feature is incompatible with qos_flows. any tos values set here
# Will be overwritten by tos values in qos_flows.
# The tos/dscp byte must be exactly that - a octet value  0 - 255, or
#    "default" to use whatever default your host has.
# Note that only multiples of 4 are usable as the two rightmost bits have
# Been redefined for use by ecn (rfc 3168 section 23.1).
# The squid parser will enforce this by masking away the ecn bits.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# None

# Tag: tcp_outgoing_mark
# Note: this option is only available if squid is rebuilt with the
# Packet mark (linux)
# Allows you to apply a netfilter mark value to outgoing packets
# On the server side, based on an acl.
# Tcp_outgoing_mark mark-value [!]aclname ...
# Example where normal_service_net uses the mark value 0x00
# And good_service_net uses 0x20
# Acl normal_service_net src 10.0.0.0/24
# Acl good_service_net src 10.0.1.0/24
# Tcp_outgoing_mark 0x00 normal_service_net
# Tcp_outgoing_mark 0x20 good_service_net
# Only fast acls are supported.
#Default:
# None

# Tag: mark_client_packet
# Note: this option is only available if squid is rebuilt with the
# Packet mark (linux)
# Allows you to apply a netfilter mark value to packets being transmitted
# On the client-side, based on an acl.
# Mark_client_packet mark-value [!]aclname ...
# Example where normal_service_net uses the mark value 0x00
# And good_service_net uses 0x20
# Acl normal_service_net src 10.0.0.0/24
# Acl good_service_net src 10.0.1.0/24
# Mark_client_packet 0x00 normal_service_net
# Mark_client_packet 0x20 good_service_net
# Note: this feature is incompatible with qos_flows. any mark values set here
# Will be overwritten by mark values in qos_flows.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# None

# Tag: mark_client_connection
# Note: this option is only available if squid is rebuilt with the
# Packet mark (linux)
# Allows you to apply a netfilter connmark value to a connection
# On the client-side, based on an acl.
# Mark_client_connection mark-value[/mask] [!]aclname ...
# The mark-value and mask are unsigned integers (hex, octal, or decimal).
# The mask may be used to preserve marking previously set by other agents
#    (e.g., iptables).
# A matching rule replaces the connmark value. if a mask is also
# Specified, then the masked bits of the original value are zeroed, and
# The configured mark-value is ored with that adjusted value.
# For example, applying a mark-value 0xab/0xf to 0x5f connmark, results
# In a 0xfb marking (rather than a 0xab or 0x5b).
# This directive semantics is similar to iptables --set-mark rather than
#    --set-xmark functionality.
# The directive does not interfere with qos_flows (which uses packet marks,
# Not connmarks).
# Example where squid marks intercepted ftp connections:
# Acl proto_ftp proto ftp
# Mark_client_connection 0x200/0xff00 proto_ftp
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# None

# Tag: qos_flows
# Allows you to select a tos/dscp value to mark outgoing
# Connections to the client, based on where the reply was sourced.
# For platforms using netfilter, allows you to set a netfilter mark
# Value instead of, or in addition to, a tos value.
# By default this functionality is disabled. to enable it with the default
# Settings simply use "qos_flows mark" or "qos_flows tos". default
# Settings will result in the netfilter mark or tos value being copied
# From the upstream connection to the client. note that it is the connection
# Connmark value not the packet mark value that is copied.
# It is not currently possible to copy the mark or tos value from the
# Client to the upstream connection request.
# Tos values really only have local significance - so you should
# Know what you're specifying. for more information, see rfc2474,
# Rfc2475, and rfc3260.
# The tos/dscp byte must be exactly that - a octet value  0 - 255.
# Note that only multiples of 4 are usable as the two rightmost bits have
# Been redefined for use by ecn (rfc 3168 section 23.1).
# The squid parser will enforce this by masking away the ecn bits.
# Mark values can be any unsigned 32-bit integer value.
# This setting is configured by setting the following values:
# Tos|mark                whether to set tos or netfilter mark values
# Local-hit=0xff        value to mark local cache hits.
# Sibling-hit=0xff    value to mark hits from sibling peers.
# Parent-hit=0xff        value to mark hits from parent peers.
# Miss=0xff[/mask]    value to mark cache misses. takes precedence
# Over the preserve-miss feature (see below), unless
# Mask is specified, in which case only the bits
# Specified in the mask are written.
# The tos variant of the following features are only possible on linux
# And require your kernel to be patched with the tos preserving zph
# Patch, available from http://zph.bratcheda.org
# No patch is needed to preserve the netfilter mark, which will work
# With all variants of netfilter.
# Disable-preserve-miss
# This option disables the preservation of the tos or netfilter
# Mark. by default, the existing tos or netfilter mark value of
# The response coming from the remote server will be retained
# And masked with miss-mark.
# Note: in the case of a netfilter mark, the mark must be set on
# The connection (using the connmark target) not on the packet
#        (mark target).
# Miss-mask=0xff
# Allows you to mask certain bits in the tos or mark value
# Received from the remote server, before copying the value to
# The tos sent towards clients.
# Default for tos: 0xff (tos from server is not changed).
# Default for mark: 0xffffffff (mark from server is not changed).
# All of these features require the --enable-zph-qos compilation flag
#    (enabled by default). Netfilter marking also requires the
# Libnetfilter_conntrack libraries (--with-netfilter-conntrack) and
# Libcap 2.09+ (--with-libcap).
#Default:
# None

# Tag: tcp_outgoing_address
# Allows you to map requests to different outgoing ip addresses
# Based on the username or source address of the user making
# The request.
# Tcp_outgoing_address ipaddr [[!]aclname] ...
# For example;
# Forwarding clients with dedicated ips for certain subnets.
# Acl normal_service_net src 10.0.0.0/24
# Acl good_service_net src 10.0.2.0/24
# Tcp_outgoing_address 2001:db8::c001 good_service_net
# Tcp_outgoing_address 10.1.0.2 good_service_net
# Tcp_outgoing_address 2001:db8::beef normal_service_net
# Tcp_outgoing_address 10.1.0.1 normal_service_net
# Tcp_outgoing_address 2001:db8::1
# Tcp_outgoing_address 10.1.0.3
# Processing proceeds in the order specified, and stops at first fully
# Matching line.
# Squid will add an implicit ip version test to each line.
# Requests going to ipv4 websites will use the outgoing 10.1.0.* addresses.
# Requests going to ipv6 websites will use the outgoing 2001:db8:* addresses.
# Note: the use of this directive using client dependent acls is
# Incompatible with the use of server side persistent connections. to
# Ensure correct results it is best to set server_persistent_connections
# To off when using this directive in such configurations.
# Note: the use of this directive to set a local ip on outgoing tcp links
# Is incompatible with using tproxy to set client ip out outbound tcp links.
# When needing to contact peers use the no-tproxy cache_peer option and the
# Client_dst_passthru directive re-enable normal forwarding such as this.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Address selection is performed by the operating system.

# Tag: host_verify_strict
# Regardless of this option setting, when dealing with intercepted
# Traffic, squid always verifies that the destination ip address matches
# The host header domain or ip (called 'authority form url').
# This enforcement is performed to satisfy a must-level requirement in
# Rfc 2616 section 14.23: "the host field value must represent the naming
# Authority of the origin server or gateway given by the original url".
# When set to on:
# Squid always responds with an http 409 (conflict) error
# Page and logs a security warning if there is no match.
# Squid verifies that the destination ip address matches
# The host header for forward-proxy and reverse-proxy traffic
# As well. for those traffic types, squid also enables the
# Following checks, comparing the corresponding host header
# And request-uri components:
# * the host names (domain or ip) must be identical,
# But valueless or missing host header disables all checks.
# For the two host names to match, both must be either ip
# Or fqdn.
# * port numbers must be identical, but if a port is missing
# The scheme-default port is assumed.
# When set to off (the default):
# Squid allows suspicious requests to continue but logs a
# Security warning and blocks caching of the response.
# * forward-proxy traffic is not checked at all.
# * reverse-proxy traffic is not checked at all.
# * intercepted traffic which passes verification is handled
# According to client_dst_passthru.
# * intercepted requests which fail verification are sent
# To the client original destination instead of direct.
# This overrides 'client_dst_passthru off'.
# For now suspicious intercepted connect requests are always
# Responded to with an http 409 (conflict) error page.
# Security note:
# As described in cve-2009-0801 when the host: header alone is used
# To determine the destination of a request it becomes trivial for
# Malicious scripts on remote websites to bypass browser same-origin
# Security policy and sandboxing protections.
# The cause of this is that such applets are allowed to perform their
# Own http stack, in which case the same-origin policy of the browser
# Sandbox only verifies that the applet tries to contact the same ip
# As from where it was loaded at the ip level. the host: header may
# Be different from the connected ip and approved origin.
#Default:
# Host_verify_strict off

# Tag: client_dst_passthru
# With nat or tproxy intercepted traffic squid may pass the request
# Directly to the original client destination ip or seek a faster
# Source using the http host header.
# Using host to locate alternative servers can provide faster
# Connectivity with a range of failure recovery options.
# But can also lead to connectivity trouble when the client and
# Server are attempting stateful interactions unaware of the proxy.
# This option (on by default) prevents alternative dns entries being
# Located to send intercepted traffic direct to an origin server.
# The clients original destination ip and port will be used instead.
# Regardless of this option setting, when dealing with intercepted
# Traffic squid will verify the host: header and any traffic which
# Fails host verification will be treated as if this option were on.
# See host_verify_strict for details on the verification process.
#Default:
# Client_dst_passthru on

# Tls options
# -----------------------------------------------------------------------------

# Tag: tls_outgoing_options
# Disable        do not support https:// urls.
# Cert=/path/to/client/certificate
# A client x.509 certificate to use when connecting.
# Key=/path/to/client/private_key
# The private key corresponding to the cert= above.
# If key= is not specified cert= is assumed to
# Reference a pem file containing both the certificate
# And private key.
# Cipher=...    the list of valid tls ciphers to use.
# Min-version=1.n
# The minimum tls protocol version to permit.
# To control sslv3 use the options= parameter.
# Supported values: 1.0 (default), 1.1, 1.2, 1.3
# Options=...    specify various tls/ssl implementation options.
# Openssl options most important are:
# No_sslv3    disallow the use of sslv3
# Single_dh_use
# Always create a new key when using
# Temporary/ephemeral dh key exchanges
# No_ticket
# Disable use of rfc5077 session tickets.
# Some servers may have problems
# Understanding the tls extension due
# To ambiguous specification in rfc4507.
# All       enable various bug workarounds
# Suggested as "harmless" by openssl
# Be warned that this reduces ssl/tls
# Strength to some attacks.
# See the openssl ssl_ctx_set_options documentation
# For a more complete list.
# Gnutls options most important are:
# %no_tickets
# Disable use of rfc5077 session tickets.
# Some servers may have problems
# Understanding the tls extension due
# To ambiguous specification in rfc4507.
# See the gnutls priority strings documentation
# For a more complete list.
# Http://www.gnutls.org/manual/gnutls.html#priority-strings
# Cafile=        pem file containing ca certificates to use when verifying
# The peer certificate. may be repeated to load multiple files.
# Capath=        a directory containing additional ca certificates to
# Use when verifying the peer certificate.
# Requires openssl or libressl.
# Crlfile=...     a certificate revocation list file to use when
# Verifying the peer certificate.
# Flags=...    specify various flags modifying the tls implementation:
# Dont_verify_peer
# Accept certificates even if they fail to
# Verify.
# Dont_verify_domain
# Don't verify the peer certificate
# Matches the server name
# Default-ca[=off]
# Whether to use the system trusted cas. default is on.
# Domain=     the peer name as advertised in its certificate.
# Used for verifying the correctness of the received peer
# Certificate. if not specified the peer hostname will be
# Used.
#Default:
# Tls_outgoing_options min-version=1.0

# Ssl options
# -----------------------------------------------------------------------------

# Tag: ssl_unclean_shutdown
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Some browsers (especially msie) bugs out on ssl shutdown
# Messages.
#Default:
# Ssl_unclean_shutdown off

# Tag: ssl_engine
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# The openssl engine to use. you will need to set this if you
# Would like to use hardware ssl acceleration for example.
# Note: openssl 3.0 and newer do not provide engine support.
#Default:
# None

# Tag: sslproxy_session_ttl
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Sets the timeout value for ssl sessions
#Default:
# Sslproxy_session_ttl 300

# Tag: sslproxy_session_cache_size
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Sets the cache size to use for ssl session
#Default:
# Sslproxy_session_cache_size 2 mb

# Tag: sslproxy_foreign_intermediate_certs
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Many origin servers fail to send their full server certificate
# Chain for verification, assuming the client already has or can
# Easily locate any missing intermediate certificates.
# Squid uses the certificates from the specified file to fill in
# These missing chains when trying to validate origin server
# Certificate chains.
# The file is expected to contain zero or more pem-encoded
# Intermediate certificates. these certificates are not treated
# As trusted root certificates, and any self-signed certificate in
# This file will be ignored.
#Default:
# None

# Tag: sslproxy_cert_sign_hash
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Sets the hashing algorithm to use when signing generated certificates.
# Valid algorithm names depend on the openssl library used. the following
# Names are usually available: sha1, sha256, sha512, and md5. please see
# Your openssl library manual for the available hashes. by default, squids
# That support this option use sha256 hashes.
# Squid does not forcefully purge cached certificates that were generated
# With an algorithm other than the currently configured one. they remain
# In the cache, subject to the regular cache eviction policy, and become
# Useful if the algorithm changes again.
#Default:
# None

# Tag: ssl_bump
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# This option is consulted when a connect request is received on
# An http_port (or a new connection is intercepted at an
# Https_port), provided that port was configured with an ssl-bump
# Flag. the subsequent data on the connection is either treated as
# Https and decrypted or tunneled at tcp level without decryption,
# Depending on the first matching bumping "action".
# Ssl_bump <action> [!]acl ...
# The following bumping actions are currently supported:
# Splice
# Become a tcp tunnel without decrypting proxied traffic.
# This is the default action.
# Bump
# When used on step sslbump1, establishes a secure connection
# With the client first, then connect to the server.
# When used on step sslbump2 or sslbump3, establishes a secure
# Connection with the server and, using a mimicked server
# Certificate, with the client.
# Peek
# Receive client (step sslbump1) or server (step sslbump2)
# Certificate while preserving the possibility of splicing the
# Connection. peeking at the server certificate (during step 2)
# Usually precludes bumping of the connection at step 3.
# Stare
# Receive client (step sslbump1) or server (step sslbump2)
# Certificate while preserving the possibility of bumping the
# Connection. staring at the server certificate (during step 2)
# Usually precludes splicing of the connection at step 3.
# Terminate
# Close client and server connections.
# Backward compatibility actions available at step sslbump1:
# Client-first
# Bump the connection. establish a secure connection with the
# Client first, then connect to the server. this old mode does
# Not allow squid to mimic server ssl certificate and does not
# Work with intercepted ssl connections.
# Server-first
# Bump the connection. establish a secure connection with the
# Server first, then establish a secure connection with the
# Client, using a mimicked server certificate. works with both
# Connect requests and intercepted ssl connections, but does
# Not allow to make decisions based on ssl handshake info.
# Peek-and-splice
# Decide whether to bump or splice the connection based on
# Client-to-squid and server-to-squid ssl hello messages.
# Xxx: remove.
# None
# Same as the "splice" action.
# All ssl_bump rules are evaluated at each of the supported bumping
# Steps.  rules with actions that are impossible at the current step are
# Ignored. the first matching ssl_bump action wins and is applied at the
# End of the current step. if no rules match, the splice action is used.
# See the at_step acl for a list of the supported sslbump steps.
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# See also: http_port ssl-bump, https_port ssl-bump, and acl at_step.
#    # Example: Bump all TLS connections except those originating from
#    # Localhost or those going to example.com.
# Acl broken_sites ssl::server_name .example.com
# Ssl_bump splice localhost
# Ssl_bump splice broken_sites
# Ssl_bump bump all
#Default:
# Become a tcp tunnel without decrypting proxied traffic.

# Tag: sslproxy_cert_error
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Use this acl to bypass server certificate validation errors.
# For example, the following lines will bypass all validation errors
# When talking to servers for example.com. all other
# Validation errors will result in err_secure_connect_fail error.
# Acl brokenbuttrustedservers dstdomain example.com
# Sslproxy_cert_error allow brokenbuttrustedservers
# Sslproxy_cert_error deny all
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# Using slow acl types may result in server crashes
# Without this option, all server certificate validation errors
# Terminate the transaction to protect squid and the client.
# Squid_x509_v_err_infinite_validation error cannot be bypassed
# But should not happen unless your openssl library is buggy.
# Security warning:
# Bypassing validation errors is dangerous because an
# Error usually implies that the server cannot be trusted
# And the connection may be insecure.
# See also: sslproxy_flags and dont_verify_peer.
#Default:
# Server certificate errors terminate the transaction.

# Tag: sslproxy_cert_sign
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Sslproxy_cert_sign <signing algorithm> acl ...
# The following certificate signing algorithms are supported:
# Signtrusted
# Sign using the configured ca certificate which is usually
# Placed in and trusted by end-user browsers. this is the
# Default for trusted origin server certificates.
# Signuntrusted
# Sign to guarantee an x509_v_err_cert_untrusted browser error.
# This is the default for untrusted origin server certificates
# That are not self-signed (see ssl::certuntrusted).
# Signself
# Sign using a self-signed certificate with the right cn to
# Generate a x509_v_err_depth_zero_self_signed_cert error in the
# Browser. this is the default for self-signed origin server
# Certificates (see ssl::certselfsigned).
# This clause only supports fast acl types.
# When sslproxy_cert_sign acl(s) match, squid uses the corresponding
# Signing algorithm to generate the certificate and ignores all
# Subsequent sslproxy_cert_sign options (the first match wins). if no
# Acl(s) match, the default signing algorithm is determined by errors
# Detected when obtaining and validating the origin server certificate.
# Warning: squid_x509_v_err_domain_mismatch and ssl:certdomainmismatch can
# Be used with sslproxy_cert_adapt, but if and only if squid is bumping a
# Connect request that carries a domain name. in all other cases (connect
# To an ip address or an intercepted ssl connection), squid cannot detect
# The domain mismatch at certificate generation time when
# Bump-server-first is used.
#Default:
# None

# Tag: sslproxy_cert_adapt
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Sslproxy_cert_adapt <adaptation algorithm> acl ...
# The following certificate adaptation algorithms are supported:
# Setvalidafter
# Sets the "not after" property to the "not after" property of
# The ca certificate used to sign generated certificates.
# Setvalidbefore
# Sets the "not before" property to the "not before" property of
# The ca certificate used to sign generated certificates.
# Setcommonname or setcommonname{cn}
# Sets subject.cn property to the host name specified as a
# Cn parameter or, if no explicit cn parameter was specified,
# Extracted from the connect request. it is a misconfiguration
# To use setcommonname without an explicit parameter for
# Intercepted or tproxied ssl connections.
# This clause only supports fast acl types.
# Squid first groups sslproxy_cert_adapt options by adaptation algorithm.
# Within a group, when sslproxy_cert_adapt acl(s) match, squid uses the
# Corresponding adaptation algorithm to generate the certificate and
# Ignores all subsequent sslproxy_cert_adapt options in that algorithm's
# Group (i.e., the first match wins within each algorithm group). if no
# Acl(s) match, the default mimicking action takes place.
# Warning: squid_x509_v_err_domain_mismatch and ssl:certdomainmismatch can
# Be used with sslproxy_cert_adapt, but if and only if squid is bumping a
# Connect request that carries a domain name. in all other cases (connect
# To an ip address or an intercepted ssl connection), squid cannot detect
# The domain mismatch at certificate generation time when
# Bump-server-first is used.
#Default:
# None

# Tag: sslpassword_program
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Specify a program used for entering ssl key passphrases
# When using encrypted ssl certificate keys. if not specified
# Keys must either be unencrypted, or squid started with the -n
# Option to allow it to query interactively for the passphrase.
# The key file name is given as argument to the program allowing
# Selection of the right password if you have multiple encrypted
# Keys.
#Default:
# None

# Options relating to external ssl_crtd
# -----------------------------------------------------------------------------

# Tag: sslcrtd_program
# Note: this option is only available if squid is rebuilt with the
#       --enable-ssl-crtd
# Specify the location and options of the executable for certificate
# Generator.
# /usr/lib/squid/security_file_certgen program can use a disk cache to improve response
# Times on repeated requests. to enable caching, specify -s and -m
# Parameters. if those parameters are not given, the program generates
# A new certificate on every request.
# For more information use:
#        /usr/lib/squid/security_file_certgen -h
#Default:
# Sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/spool/squid/ssl_db -m 4mb

# Tag: sslcrtd_children
# Note: this option is only available if squid is rebuilt with the
#       --enable-ssl-crtd
# Specifies the maximum number of certificate generation processes that
# Squid may spawn (numberofchildren) and several related options. using
# Too few of these helper processes (a.k.a. "helpers") creates request
# Queues. using too many helpers wastes your system resources. squid
# Does not support spawning more than 32 helpers.
# Usage: numberofchildren [option]...
# The startup= and idle= options allow some measure of skew in your
# Tuning.
# Startup=n
# Sets the minimum number of processes to spawn when squid
# Starts or reconfigures. when set to zero the first request will
# Cause spawning of the first child process to handle it.
# Starting too few children temporary slows squid under load while it
# Tries to spawn enough additional processes to cope with traffic.
# Idle=n
# Sets a minimum of how many processes squid is to try and keep available
# At all times. when traffic begins to rise above what the existing
# Processes can handle this many more will be spawned up to the maximum
# Configured. a minimum setting of 1 is required.
# Queue-size=n
# Sets the maximum number of queued requests. a request is queued when
# No existing child is idle and no new child can be started due to
# Numberofchildren limit. if the queued requests exceed queue size for
# More than 3 minutes squid aborts its operation. the default value is
# Set to 2*numberofchildren.
# You must have at least one ssl_crtd process.
#Default:
# Sslcrtd_children 32 startup=5 idle=1

# Tag: sslcrtvalidator_program
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Specify the location and options of the executable for ssl_crt_validator
# Process.
# Usage:  sslcrtvalidator_program [ttl=n] [cache=n] path ...
# Options:
# Ttl=n         ttl in seconds for cached results. the default is 60 secs
# Cache=n       limit the result cache size. the default value is 2048
#Default:
# None

# Tag: sslcrtvalidator_children
# Note: this option is only available if squid is rebuilt with the
#       --with-openssl
# Specifies the maximum number of certificate validation processes that
# Squid may spawn (numberofchildren) and several related options. using
# Too few of these helper processes (a.k.a. "helpers") creates request
# Queues. using too many helpers wastes your system resources. squid
# Does not support spawning more than 32 helpers.
# Usage: numberofchildren [option]...
# The startup= and idle= options allow some measure of skew in your
# Tuning.
# Startup=n
# Sets the minimum number of processes to spawn when squid
# Starts or reconfigures. when set to zero the first request will
# Cause spawning of the first child process to handle it.
# Starting too few children temporary slows squid under load while it
# Tries to spawn enough additional processes to cope with traffic.
# Idle=n
# Sets a minimum of how many processes squid is to try and keep available
# At all times. when traffic begins to rise above what the existing
# Processes can handle this many more will be spawned up to the maximum
# Configured. a minimum setting of 1 is required.
# Concurrency=
# The number of requests each certificate validator helper can handle in
# Parallel. a value of 0 indicates the certficate validator does not
# Support concurrency. defaults to 1.
# When this directive is set to a value >= 1 then the protocol
# Used to communicate with the helper is modified to include
# A request id in front of the request/response. the request
# Id from the request must be echoed back with the response
# To that request.
# Queue-size=n
# Sets the maximum number of queued requests. a request is queued when
# No existing child can accept it due to concurrency limit and no new
# Child can be started due to numberofchildren limit. if the queued
# Requests exceed queue size for more than 3 minutes squid aborts its
# Operation. the default value is set to 2*numberofchildren.
# You must have at least one ssl_crt_validator process.
#Default:
# Sslcrtvalidator_children 32 startup=5 idle=1 concurrency=1

# Options which affect the neighbor selection algorithm
# -----------------------------------------------------------------------------

# Tag: cache_peer
# To specify other caches in a hierarchy, use the format:
# Cache_peer hostname type http-port icp-port [options]
# For example,
# #                                        Proxy  icp
#    #          Hostname             type     port   port  options
#    #          -------------------- -------- ----- -----  -----------
# Cache_peer parent.foo.net       parent    3128  3130  default
# Cache_peer sib1.foo.net         sibling   3128  3130  proxy-only
# Cache_peer sib2.foo.net         sibling   3128  3130  proxy-only
# Cache_peer example.com          parent    80       0  default
# Cache_peer cdn.example.com      sibling   3128     0
# Type:    either 'parent', 'sibling', or 'multicast'.
# Proxy-port:    the port number where the peer accept http requests.
# For other squid proxies this is usually 3128
# For web servers this is usually 80
# Icp-port:    used for querying neighbor caches about objects.
# Set to 0 if the peer does not support icp or htcp.
# See icp and htcp options below for additional details.
#    ==== icp OPTIONS ====
# You must also set icp_port and icp_access explicitly when using these options.
# The defaults will prevent peer traffic using icp.
# No-query    disable icp queries to this neighbor.
# Multicast-responder
# Indicates the named peer is a member of a multicast group.
# Icp queries will not be sent directly to the peer, but icp
# Replies will be accepted from it.
# Closest-only    indicates that, for icp_op_miss replies, we'll only forward
# Closest_parent_misses and never first_parent_misses.
# Background-ping
# To only send icp queries to this neighbor infrequently.
# This is used to keep the neighbor round trip time updated
# And is usually used in conjunction with weighted-round-robin.
#    ==== htcp OPTIONS ====
# You must also set htcp_port and htcp_access explicitly when using these options.
# The defaults will prevent peer traffic using htcp.
# Htcp        send htcp, instead of icp, queries to the neighbor.
# You probably also want to set the "icp-port" to 4827
# Instead of 3130. this directive accepts a comma separated
# List of options described below.
# Htcp=oldsquid    send htcp to old squid versions (2.5 or earlier).
# Htcp=no-clr    send htcp to the neighbor but without
# Sending any clr requests.  this cannot be used with
# Only-clr.
# Htcp=only-clr    send htcp to the neighbor but only clr requests.
# This cannot be used with no-clr.
# Htcp=no-purge-clr
# Send htcp to the neighbor including clrs but only when
# They do not result from purge requests.
# Htcp=forward-clr
# Forward any htcp clr requests this proxy receives to the peer.
#    ==== peer SELECTION METHODS ====
# The default peer selection method is icp, with the first responding peer
# Being used as source. these options can be used for better load balancing.
# Default        this is a parent cache which can be used as a "last-resort"
# If a peer cannot be located by any of the peer-selection methods.
# If specified more than once, only the first is used.
# Round-robin    load-balance parents which should be used in a round-robin
# Fashion in the absence of any icp queries.
# Weight=n can be used to add bias.
# Weighted-round-robin
# Load-balance parents which should be used in a round-robin
# Fashion with the frequency of each parent being based on the
# Round trip time. closer parents are used more often.
# Usually used for background-ping parents.
# Weight=n can be used to add bias.
# Carp        load-balance parents which should be used as a carp array.
# The requests will be distributed among the parents based on the
# Carp load balancing hash function based on their weight.
# Userhash    load-balance parents based on the client proxy_auth or ident username.
# Sourcehash    load-balance parents based on the client source ip.
# Multicast-siblings
# To be used only for cache peers of type "multicast".
# All members of this multicast group have "sibling"
# Relationship with it, not "parent".  this is to a multicast
# Group when the requested object would be fetched only from
# A "parent" cache, anyway.  it's useful, e.g., when
# Configuring a pool of redundant squid proxies, being
# Members of the same multicast group.
#    ==== peer SELECTION OPTIONS ====
# Weight=n    use to affect the selection of a peer during any weighted
# Peer-selection mechanisms.
# The weight must be an integer; default is 1,
# Larger weights are favored more.
# This option does not affect parent selection if a peering
# Protocol is not in use.
# Basetime=n    specify a base amount to be subtracted from round trip
# Times of parents.
# It is subtracted before division by weight in calculating
# Which parent to fectch from. if the rtt is less than the
# Base time the rtt is set to a minimal value.
# Ttl=n        specify a ttl to use when sending multicast icp queries
# To this address.
# Only useful when sending to a multicast group.
# Because we don't accept icp replies from random
# Hosts, you must configure other group members as
# Peers with the 'multicast-responder' option.
# No-delay    to prevent access to this neighbor from influencing the
# Delay pools.
# Digest-url=url    tell squid to fetch the cache digest (if digests are
# Enabled) for this host from the specified url rather
# Than the squid default location.
#    ==== carp OPTIONS ====
# Carp-key=key-specification
# Use a different key than the full url to hash against the peer.
# The key-specification is a comma-separated list of the keywords
# Scheme, host, port, path, params
# Order is not important.
# ==== accelerator / reverse-proxy options ====
# Originserver    causes this parent to be contacted as an origin server.
# Meant to be used in accelerator setups when the peer
# Is a web server.
# Forceddomain=name
# Set the host header of requests forwarded to this peer.
# Useful in accelerator setups where the server (peer)
# Expects a certain domain name but clients may request
# Others. ie example.com or www.example.com
# No-digest    disable request of cache digests.
# No-netdb-exchange
# Disables requesting icmp rtt database (netdb).
#    ==== authentication OPTIONS ====
# Login=user:password
# If this is a personal/workgroup proxy and your parent
# Requires proxy authentication.
# Note: the string can include url escapes (i.e. %20 for
# Spaces). this also means % must be written as %%.
# Login=passthru
# Send login details received from client to this peer.
# Both proxy- and www-authorization headers are passed
# Without alteration to the peer.
# Authentication is not required by squid for this to work.
# Note: this will pass any form of authentication but
# Only basic auth will work through a proxy unless the
# Connection-auth options are also used.
# Login=pass    send login details received from client to this peer.
# Authentication is not required by this option.
# If there are no client-provided authentication headers
# To pass on, but username and password are available
# From an external acl user= and password= result tags
# They may be sent instead.
# Note: to combine this with proxy_auth both proxies must
# Share the same user database as http only allows for
# A single login (one for proxy, one for origin server).
# Also be warned this will expose your users proxy
# Password to the peer. use with caution
# Login=*:password
# Send the username to the upstream cache, but with a
# Fixed password. this is meant to be used when the peer
# Is in another administrative domain, but it is still
# Needed to identify each user.
# The star can optionally be followed by some extra
# Information which is added to the username. this can
# Be used to identify this proxy to the peer, similar to
# The login=username:password option above.
# Login=negotiate
# If this is a personal/workgroup proxy and your parent
# Requires a secure proxy authentication.
# The first principal from the default keytab or defined by
# The environment variable krb5_ktname will be used.
# Warning: the connection may transmit requests from multiple
# Clients. negotiate often assumes end-to-end authentication
# And a single-client. which is not strictly true here.
# Login=negotiate:principal_name
# If this is a personal/workgroup proxy and your parent
# Requires a secure proxy authentication.
# The principal principal_name from the default keytab or
# Defined by the environment variable krb5_ktname will be
# Used.
# Warning: the connection may transmit requests from multiple
# Clients. negotiate often assumes end-to-end authentication
# And a single-client. which is not strictly true here.
# Connection-auth=on|off
# Tell squid that this peer does or not support microsoft
# Connection oriented authentication, and any such
# Challenges received from there should be ignored.
# Default is auto to automatically determine the status
# Of the peer.
# Auth-no-keytab
# Do not use a keytab to authenticate to a peer when
# Login=negotiate is specified. let the gssapi
# Implementation determine which already existing
# Credentials cache to use instead.
#    ==== ssl / HTTPS / TLS OPTIONS ====
# Tls        encrypt connections to this peer with tls.
# Sslcert=/path/to/ssl/certificate
# A client x.509 certificate to use when connecting to
# This peer.
# Sslkey=/path/to/ssl/key
# The private key corresponding to sslcert above.
# If sslkey= is not specified sslcert= is assumed to
# Reference a pem file containing both the certificate
# And private key.
# Notes:
# On debian/ubuntu systems a default snakeoil certificate is
# Available in /etc/ssl and users can set:
# Sslcert=/etc/ssl/certs/ssl-cert-snakeoil.pem
# And
# Sslkey=/etc/ssl/private/ssl-cert-snakeoil.key
# For testing.
# Sslcipher=...    the list of valid ssl ciphers to use when connecting
# To this peer.
# Tls-min-version=1.n
# The minimum tls protocol version to permit. to control
# Sslv3 use the tls-options= parameter.
# Supported values: 1.0 (default), 1.1, 1.2
# Tls-options=...    specify various tls implementation options.
# Openssl options most important are:
# No_sslv3    disallow the use of sslv3
# Single_dh_use
# Always create a new key when using
# Temporary/ephemeral dh key exchanges
# No_ticket
# Disable use of rfc5077 session tickets.
# Some servers may have problems
# Understanding the tls extension due
# To ambiguous specification in rfc4507.
# All       enable various bug workarounds
# Suggested as "harmless" by openssl
# Be warned that this reduces ssl/tls
# Strength to some attacks.
# See the openssl ssl_ctx_set_options documentation for a
# More complete list.
# Gnutls options most important are:
# %no_tickets
# Disable use of rfc5077 session tickets.
# Some servers may have problems
# Understanding the tls extension due
# To ambiguous specification in rfc4507.
# See the gnutls priority strings documentation
# For a more complete list.
# Http://www.gnutls.org/manual/gnutls.html#priority-strings
# Tls-cafile=    pem file containing ca certificates to use when verifying
# The peer certificate. may be repeated to load multiple files.
# Sslcapath=...    a directory containing additional ca certificates to
# Use when verifying the peer certificate.
# Requires openssl or libressl.
# Sslcrlfile=...     a certificate revocation list file to use when
# Verifying the peer certificate.
# Sslflags=...    specify various flags modifying the ssl implementation:
# Dont_verify_peer
# Accept certificates even if they fail to
# Verify.
# Dont_verify_domain
# Don't verify the peer certificate
# Matches the server name
# Ssldomain=     the peer name as advertised in it's certificate.
# Used for verifying the correctness of the received peer
# Certificate. if not specified the peer hostname will be
# Used.
# Front-end-https[=off|on|auto]
# Enable the "front-end-https: on" header needed when
# Using squid as a ssl frontend in front of microsoft owa.
# See ms kb document q307347 for details on this header.
# If set to auto the header will only be added if the
# Request is forwarded as a https:// url.
# Tls-default-ca[=off]
# Whether to use the system trusted cas. default is on.
# Tls-no-npn    do not use the tls npn extension to advertise http/1.1.
# ==== general options ====
# Connect-timeout=n
# A peer-specific connect timeout.
# Also see the peer_connect_timeout directive.
# Connect-fail-limit=n
# How many times connecting to a peer must fail before
# It is marked as down. standby connection failures
# Count towards this limit. default is 10.
# Allow-miss    disable squid's use of only-if-cached when forwarding
# Requests to siblings. this is primarily useful when
# Icp_hit_stale is used by the sibling. excessive use
# Of this option may result in forwarding loops. one way
# To prevent peering loops when using this option, is to
# Deny cache peer usage on requests from a peer:
# Acl frompeer ...
# Cache_peer_access peername deny frompeer
# Max-conn=n     limit the number of concurrent connections the squid
# May open to this peer, including already opened idle
# And standby connections. there is no peer-specific
# Connection limit by default.
# A peer exceeding the limit is not used for new
# Requests unless a standby connection is available.
# Max-conn currently works poorly with idle persistent
# Connections: when a peer reaches its max-conn limit,
# And there are idle persistent connections to the peer,
# The peer may not be selected because the limiting code
# Does not know whether squid can reuse those idle
# Connections.
# Standby=n    maintain a pool of n "hot standby" connections to an
# Up peer, available for requests when no idle
# Persistent connection is available (or safe) to use.
# By default and with zero n, no such pool is maintained.
# N must not exceed the max-conn limit (if any).
# At start or after reconfiguration, squid opens new tcp
# Standby connections until there are n connections
# Available and then replenishes the standby pool as
# Opened connections are used up for requests. a used
# Connection never goes back to the standby pool, but
# May go to the regular idle persistent connection pool
# Shared by all peers and origin servers.
# Squid never opens multiple new standby connections
# Concurrently.  this one-at-a-time approach minimizes
# Flooding-like effect on peers. furthermore, just a few
# Standby connections should be sufficient in most cases
# To supply most new requests with a ready-to-use
# Connection.
# Standby connections obey server_idle_pconn_timeout.
# For the feature to work as intended, the peer must be
# Configured to accept and keep them open longer than
# The idle timeout at the connecting squid, to minimize
# Race conditions typical to idle used persistent
# Connections. default request_timeout and
# Server_idle_pconn_timeout values ensure such a
# Configuration.
# Name=xxx    unique name for the peer.
# Required if you have multiple peers on the same host
# But different ports.
# This name can be used in cache_peer_access and similar
# Directives to identify the peer.
# Can be used by outgoing access controls through the
# Peername acl type.
# No-tproxy    do not use the client-spoof tproxy support when forwarding
# Requests to this peer. use normal address selection instead.
# This overrides the spoof_client_ip acl.
# Proxy-only    objects fetched from the peer will not be stored locally.
#Default:
# None

# Tag: cache_peer_access
# Restricts usage of cache_peer proxies.
# Usage:
# Cache_peer_access peer-name allow|deny [!]aclname ...
# For the required peer-name parameter, use either the value of the
# Cache_peer name=value parameter or, if name=value is missing, the
# Cache_peer hostname parameter.
# This directive narrows down the selection of peering candidates, but
# Does not determine the order in which the selected candidates are
# Contacted. that order is determined by the peer selection algorithms
#    (see PEER SELECTION sections in the cache_peer documentation).
# If a deny rule matches, the corresponding peer will not be contacted
# For the current transaction -- squid will not send icp queries and
# Will not forward http requests to that peer. an allow match leaves
# The corresponding peer in the selection. the first match for a given
# Peer wins for that peer.
# The relative order of cache_peer_access directives for the same peer
# Matters. the relative order of any two cache_peer_access directives
# For different peers does not matter. to ease interpretation, it is a
# Good idea to group cache_peer_access directives for the same peer
# Together.
# A single cache_peer_access directive may be evaluated multiple times
# For a given transaction because individual peer selection algorithms
# May check it independently from each other. these redundant checks
# May be optimized away in future squid versions.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# No peer usage restrictions.

# Tag: neighbor_type_domain
# Modify the cache_peer neighbor type when passing requests
# About specific domains to the peer.
# Usage:
# Neighbor_type_domain neighbor parent|sibling domain domain ...
# For example:
# Cache_peer foo.example.com parent 3128 3130
# Neighbor_type_domain foo.example.com sibling .au .de
# The above configuration treats all requests to foo.example.com as a
# Parent proxy unless the request is for a .au or .de cctld domain name.
#Default:
# The peer type from cache_peer directive is used for all requests to that peer.

# Tag: dead_peer_timeout    (seconds)
# This controls how long squid waits to declare a peer cache
# As "dead."  if there are no icp replies received in this
# Amount of time, squid will declare the peer dead and not
# Expect to receive any further icp replies.  however, it
# Continues to send icp queries, and will mark the peer as
# Alive upon receipt of the first subsequent icp reply.
# This timeout also affects when squid expects to receive icp
# Replies from peers.  if more than 'dead_peer' seconds have
# Passed since the last icp reply was received, squid will not
# Expect to receive an icp reply on the next query.  thus, if
# Your time between requests is greater than this timeout, you
# Will see a lot of requests sent direct to origin servers
# Instead of to your parents.
#Default:
# Dead_peer_timeout 10 seconds

# Tag: forward_max_tries
# Limits the number of attempts to forward the request.
# For the purpose of this limit, squid counts all high-level request
# Forwarding attempts, including any same-destination retries after
# Certain persistent connection failures and any attempts to use a
# Different peer. however, low-level connection reopening attempts
#    (enabled using connect_retries) are not counted.
# See also: forward_timeout and connect_retries.
#Default:
# Forward_max_tries 25

# Memory cache options
# -----------------------------------------------------------------------------

# Tag: cache_mem    (bytes)
# Note: this parameter does not specify the maximum process size.
# It only places a limit on how much additional memory squid will
# Use as a memory cache of objects. squid uses memory for other
# Things as well. see the squid faq section 8 for details.
# 'cache_mem' specifies the ideal amount of memory to be used
# For:
#        * in-Transit objects
#        * hot Objects
#        * negative-Cached objects
# Data for these objects are stored in 4 kb blocks.  this
# Parameter specifies the ideal upper limit on the total size of
# 4 kb blocks allocated.  in-transit objects take the highest
# Priority.
# In-transit objects have priority over the others.  when
# Additional space is needed for incoming data, negative-cached
# And hot objects will be released.  in other words, the
# Negative-cached and hot objects will fill up any unused space
# Not needed for in-transit objects.
# If circumstances require, this limit will be exceeded.
# Specifically, if your incoming request rate requires more than
#    'cache_mem' of memory to hold in-transit objects, Squid will
# Exceed this limit to satisfy the new requests.  when the load
# Decreases, blocks will be freed until the high-water mark is
# Reached.  thereafter, blocks will be used to store hot
# Objects.
# If shared memory caching is enabled, squid does not use the shared
# Cache space for in-transit objects, but they still consume as much
# Local memory as they need. for more details about the shared memory
# Cache, see memory_cache_shared.
#Default:
# Cache_mem 256 mb

# Tag: maximum_object_size_in_memory    (bytes)
# Objects greater than this size will not be attempted to kept in
# The memory cache. this should be set high enough to keep objects
# Accessed frequently in memory to improve performance whilst low
# Enough to keep larger objects from hoarding cache_mem.
#Default:
# Maximum_object_size_in_memory 768 kb

# Tag: memory_cache_shared    on|off
# Controls whether the memory cache is shared among smp workers.
# The shared memory cache is meant to occupy cache_mem bytes and replace
# The non-shared memory cache, although some entities may still be
# Cached locally by workers for now (e.g., internal and in-transit
# Objects may be served from a local memory cache even if shared memory
# Caching is enabled).
# By default, the memory cache is shared if and only if all of the
# Following conditions are satisfied: squid runs in smp mode with
# Multiple workers, cache_mem is positive, and squid environment
# Supports required ipc primitives (e.g., posix shared memory segments
# And gcc-style atomic operations).
# To avoid blocking locks, shared memory uses opportunistic algorithms
# That do not guarantee that every cachable entity that could have been
# Shared among smp workers will actually be shared.
#Default:
# "on" where supported if doing memory caching with multiple SMP workers.

# Tag: memory_cache_mode disk
# Controls which objects to keep in the memory cache (cache_mem)
# Always    keep most recently fetched objects in memory (default)
# Disk    only disk cache hits are kept in memory, which means
# An object must first be cached on disk and then hit
# A second time before cached in memory.
# Network    only objects fetched from network is kept in memory
#Default:
# Keep the most recently fetched objects in memory

# Tag: memory_replacement_policy
# The memory replacement policy parameter determines which
# Objects are purged from memory when memory space is needed.
# See cache_replacement_policy for details on algorithms.
#Default:
# Memory_replacement_policy lru

# Disk cache options
# -----------------------------------------------------------------------------

# Tag: cache_replacement_policy
# The cache replacement policy parameter determines which
# Objects are evicted (replaced) when disk space is needed.
# Lru       : squid's original list based lru policy
# Heap gdsf : greedy-dual size frequency
# Heap lfuda: least frequently used with dynamic aging
# Heap lru  : lru policy implemented using a heap
# Applies to any cache_dir lines listed below this directive.
# The lru policies keeps recently referenced objects.
# The heap gdsf policy optimizes object hit rate by keeping smaller
# Popular objects in cache so it has a better chance of getting a
# Hit.  it achieves a lower byte hit rate than lfuda though since
# It evicts larger (possibly popular) objects.
# The heap lfuda policy keeps popular objects in cache regardless of
# Their size and thus optimizes byte hit rate at the expense of
# Hit rate since one large, popular object will prevent many
# Smaller, slightly less popular objects from being cached.
# Both policies utilize a dynamic aging mechanism that prevents
# Cache pollution that can otherwise occur with frequency-based
# Replacement policies.
# Note: if using the lfuda replacement policy you should increase
# The value of maximum_object_size above its default of 4 mb to
# To maximize the potential byte hit rate improvement of lfuda.
# For more information about the gdsf and lfuda cache replacement
# Policies see http://www.hpl.hp.com/techreports/1999/hpl-1999-69.html
# And http://fog.hpl.external.hp.com/techreports/98/hpl-98-173.html.
#Default:
# Cache_replacement_policy lru

# Tag: minimum_object_size    (bytes)
# Objects smaller than this size will not be saved on disk.  the
# Value is specified in bytes, and the default is 0 kb, which
# Means all responses can be stored.
#Default:
# No limit

# Tag: maximum_object_size    (bytes)
# Set the default value for max-size parameter on any cache_dir.
# The value is specified in bytes, and the default is 4 mb.
# If you wish to get a high bytes hit ratio, you should probably
# Increase this (one 32 mb object hit counts for 3200 10kb
# Hits).
# If you wish to increase hit ratio more than you want to
# Save bandwidth you should leave this low.
# Note: if using the lfuda replacement policy you should increase
# This value to maximize the byte hit rate improvement of lfuda!
# See cache_replacement_policy for a discussion of this policy.
#Default:
# Maximum_object_size 4 mb

# Tag: cache_dir
# Format:
# Cache_dir type directory-name fs-specific-data [options]
# You can specify multiple cache_dir lines to spread the
# Cache among different disk partitions.
# Type specifies the kind of storage system to use. only "ufs"
# Is built by default. to enable any of the other storage systems
# See the --enable-storeio configure option.
# 'directory' is a top-level directory where cache swap
# Files will be stored.  if you want to use an entire disk
# For caching, this can be the mount-point directory.
# The directory must exist and be writable by the squid
# Process.  squid will not create this directory for you.
# In smp configurations, cache_dir must not precede the workers option
# And should use configuration macros or conditionals to give each
# Worker interested in disk caching a dedicated cache directory.
#    ====  the ufs store type  ====
# "ufs" is the old well-known squid storage format that has always
# Been there.
# Usage:
# Cache_dir ufs directory-name mbytes l1 l2 [options]
# 'mbytes' is the amount of disk space (mb) to use under this
# Directory.  the default is 100 mb.  change this to suit your
# Configuration.  do not put the size of your disk drive here.
# Instead, if you want squid to use the entire disk drive,
# Subtract 20% and use that value.
# 'l1' is the number of first-level subdirectories which
# Will be created under the 'directory'.  the default is 16.
# 'l2' is the number of second-level subdirectories which
# Will be created under each first-level directory.  the default
# Is 256.
#    ====  the aufs store type  ====
# "aufs" uses the same storage format as "ufs", utilizing
# Posix-threads to avoid blocking the main squid process on
# Disk-i/o. this was formerly known in squid as async-io.
# Usage:
# Cache_dir aufs directory-name mbytes l1 l2 [options]
# See argument descriptions under ufs above
#    ====  the diskd store type  ====
# "diskd" uses the same storage format as "ufs", utilizing a
# Separate process to avoid blocking the main squid process on
# Disk-i/o.
# Usage:
# Cache_dir diskd directory-name mbytes l1 l2 [options] [q1=n] [q2=n]
# See argument descriptions under ufs above
# Q1 specifies the number of unacknowledged i/o requests when squid
# Stops opening new files. if this many messages are in the queues,
# Squid won't open new files. default is 64
# Q2 specifies the number of unacknowledged messages when squid
# Starts blocking.  if this many messages are in the queues,
# Squid blocks until it receives some replies. default is 72
# When q1 < q2 (the default), the cache directory is optimized
# For lower response time at the expense of a decrease in hit
# Ratio.  if q1 > q2, the cache directory is optimized for
# Higher hit ratio at the expense of an increase in response
# Time.
#    ====  the rock store type  ====
# Usage:
# Cache_dir rock directory-name mbytes [options]
# The rock store type is a database-style storage. all cached
# Entries are stored in a "database" file, using fixed-size slots.
# A single entry occupies one or more slots.
# If possible, squid using rock store creates a dedicated kid
# Process called "disker" to avoid blocking squid worker(s) on disk
# I/o. one disker kid is created for each rock cache_dir.  diskers
# Are created only when squid, running in daemon mode, has support
# For the ipcio disk i/o module.
# Swap-timeout=msec: squid will not start writing a miss to or
# Reading a hit from disk if it estimates that the swap operation
# Will take more than the specified number of milliseconds. by
# Default and when set to zero, disables the disk i/o time limit
# Enforcement. ignored when using blocking i/o module because
# Blocking synchronous i/o does not allow squid to estimate the
# Expected swap wait time.
# Max-swap-rate=swaps/sec: artificially limits disk access using
# The specified i/o rate limit. swap out requests that
# Would cause the average i/o rate to exceed the limit are
# Delayed. individual swap in requests (i.e., hits or reads) are
# Not delayed, but they do contribute to measured swap rate and
# Since they are placed in the same fifo queue as swap out
# Requests, they may wait longer if max-swap-rate is smaller.
# This is necessary on file systems that buffer "too
# Many" writes and then start blocking squid and other processes
# While committing those writes to disk.  usually used together
# With swap-timeout to avoid excessive delays and queue overflows
# When disk demand exceeds available disk "bandwidth". by default
# And when set to zero, disables the disk i/o rate limit
# Enforcement. currently supported by ipcio module only.
# Slot-size=bytes: the size of a database "record" used for
# Storing cached responses. a cached response occupies at least
# One slot and all database i/o is done using individual slots so
# Increasing this parameter leads to more disk space waste while
# Decreasing it leads to more disk i/o overheads. should be a
# Multiple of your operating system i/o page size. defaults to
# 16kbytes. a housekeeping header is stored with each slot and
# Smaller slot-sizes will be rejected. the header is smaller than
# 100 bytes.
#    ==== common OPTIONS ====
# No-store    no new objects should be stored to this cache_dir.
# Min-size=n    the minimum object size in bytes this cache_dir
# Will accept.  it's used to restrict a cache_dir
# To only store large objects (e.g. aufs) while
# Other stores are optimized for smaller objects
#            (e.g. Rock).
# Defaults to 0.
# Max-size=n    the maximum object size in bytes this cache_dir
# Supports.
# The value in maximum_object_size directive sets
# The default unless more specific details are
# Available (ie a small store capacity).
# Note: to make optimal use of the max-size limits you should order
# The cache_dir lines with the smallest max-size value first.
#Default:
# No disk cache. store cache ojects only in memory.
# Tag: store_dir_select_algorithm
# How squid selects which cache_dir to use when the response
# Object will fit into more than one.
# Regardless of which algorithm is used the cache_dir min-size
# And max-size parameters are obeyed. as such they can affect
# The selection algorithm by limiting the set of considered
# Cache_dir.
# Algorithms:
# Least-load
# This algorithm is suited to caches with similar cache_dir
# Sizes and disk speeds.
# The disk with the least i/o pending is selected.
# When there are multiple disks with the same i/o load ranking
# The cache_dir with most available capacity is selected.
# When a mix of cache_dir sizes are configured the faster disks
# Have a naturally lower i/o loading and larger disks have more
# Capacity. so space used to store objects and data throughput
# May be very unbalanced towards larger disks.
# Round-robin
# This algorithm is suited to caches with unequal cache_dir
# Disk sizes.
# Each cache_dir is selected in a rotation. the next suitable
# Cache_dir is used.
# Available cache_dir capacity is only considered in relation
# To whether the object will fit and meets the min-size and
# Max-size parameters.
# Disk i/o loading is only considered to prevent overload on slow
# Disks. this algorithm does not spread objects by size, so any
# I/o loading per-disk may appear very unbalanced and volatile.
# If several cache_dirs use similar min-size, max-size, or other
# Limits to to reject certain responses, then do not group such
# Cache_dir lines together, to avoid round-robin selection bias
# Towards the first cache_dir after the group. instead, interleave
# Cache_dir lines from different groups. for example:
# Store_dir_select_algorithm round-robin
# Cache_dir rock /hdd1 ... min-size=100000
# Cache_dir rock /ssd1 ... max-size=99999
# Cache_dir rock /hdd2 ... min-size=100000
# Cache_dir rock /ssd2 ... max-size=99999
# Cache_dir rock /hdd3 ... min-size=100000
# Cache_dir rock /ssd3 ... max-size=99999
#Default:
# Store_dir_select_algorithm least-load

# Tag: max_open_disk_fds
# To avoid having disk as the i/o bottleneck squid can optionally
# Bypass the on-disk cache if more than this amount of disk file
# Descriptors are open.
# A value of 0 indicates no limit.
#Default:
# No limit

# Tag: cache_swap_low    (percent, 0-100)
# The low-water mark for aufs/ufs/diskd cache object eviction by
# The cache_replacement_policy algorithm.
# Removal begins when the swap (disk) usage of a cache_dir is
# Above this low-water mark and attempts to maintain utilization
# Near the low-water mark.
# As swap utilization increases towards the high-water mark set
# By cache_swap_high object eviction becomes more agressive.
# The value difference in percentages between low- and high-water
# Marks represent an eviction rate of 300 objects per second and
# The rate continues to scale in agressiveness by multiples of
# This above the high-water mark.
# Defaults are 90% and 95%. if you have a large cache, 5% could be
# Hundreds of mb. if this is the case you may wish to set these
# Numbers closer together.
# See also cache_swap_high and cache_replacement_policy
#Default:
# Cache_swap_low 90

# Tag: cache_swap_high    (percent, 0-100)
# The high-water mark for aufs/ufs/diskd cache object eviction by
# The cache_replacement_policy algorithm.
# Removal begins when the swap (disk) usage of a cache_dir is
# Above the low-water mark set by cache_swap_low and attempts to
# Maintain utilization near the low-water mark.
# As swap utilization increases towards this high-water mark object
# Eviction becomes more agressive.
# The value difference in percentages between low- and high-water
# Marks represent an eviction rate of 300 objects per second and
# The rate continues to scale in agressiveness by multiples of
# This above the high-water mark.
# Defaults are 90% and 95%. if you have a large cache, 5% could be
# Hundreds of mb. if this is the case you may wish to set these
# Numbers closer together.
# See also cache_swap_low and cache_replacement_policy
#Default:
# Cache_swap_high 95

# Logfile options
# -----------------------------------------------------------------------------

# Tag: logformat
# Usage:
# Logformat <name> <format specification>
# Defines an access log format.
# The <format specification> is a string with embedded % format codes
# % format codes all follow the same basic structure where all
# Components but the formatcode are optional and usually unnecessary,
# Especially when dealing with common codes.
# % [encoding] [-] [[0]width] [{arg}] formatcode [{arg}]
# Encoding escapes or otherwise protects "special" characters:
# "    quoted string encoding where quote(") and
# Backslash(\) characters are \-escaped while
# Cr, lf, and tab characters are encoded as \r,
#                \n, and \t two-character sequences.
# [    custom squid encoding where percent(%), square
# Brackets([]), backslash(\) and characters with
# Codes outside of [32,126] range are %-encoded.
# Sp is not encoded. used by log_mime_hdrs.
# #    Url encoding (a.k.a. percent-encoding) where
# All url unsafe and control characters (per rfc
# 1738) are %-encoded.
# /    shell-like encoding where quote(") and
# Backslash(\) characters are \-escaped while cr
# And lf characters are encoded as \r and \n
# Two-character sequences. values containing sp
# Character(s) are surrounded by quotes(").
# '    raw/as-is encoding with no escaping/quoting.
# Default encoding: when no explicit encoding is
# Specified, each %code determines its own encoding.
# Most %codes use raw/as-is encoding, but some codes use
# A so called "pass-through url encoding" where all url
# Unsafe and control characters (per rfc 1738) are
#            %-encoded, but the percent character(%) is left as is.
# -    left aligned
# Width    minimum and/or maximum field width:
#                [width_min][.width_max]
# When minimum starts with 0, the field is zero-padded.
# String values exceeding maximum width are truncated.
# {arg}    argument such as header name etc. this field may be
# Placed before or after the token, but not both at once.
# Format codes:
# %    a literal % character
# Sn    unique sequence number per log line entry
# Err_code    the id of an error response served by squid or
# A similar internal error identifier.
# Err_detail  additional err_code-dependent error information.
# Note    the annotation specified by the argument. also
# Logs the adaptation meta headers set by the
# Adaptation_meta configuration parameter.
# If no argument given all annotations logged.
# The argument may include a separator to use with
# Annotation values:
# Name[:separator]
# By default, multiple note values are separated with ","
# And multiple notes are separated with "\r\n".
# When logging named notes with %{name}note, the
# Explicitly configured separator is used between note
# Values. when logging all notes with %note, the
# Explicitly configured separator is used between
# Individual notes. there is currently no way to
# Specify both value and notes separators when logging
# All notes with %note.
# Master_xaction  the master transaction identifier is an unsigned
# Integer. these ids are guaranteed to monotonically
# Increase within a single worker process lifetime, with
# Higher values corresponding to transactions that were
# Accepted or initiated later. due to current implementation
# Deficiencies, some ids are skipped (i.e. never logged).
# Concurrent workers and restarted workers use similar,
# Overlapping sequences of master transaction ids.
# Connection related format codes:
# >a    client source ip address
#        >a    Client FQDN
#        >p    Client source port
#        >eui    Client source EUI (MAC address, EUI-48 or EUI-64 identifier)
#        >la    Local IP address the client connected to
#        >lp    Local port number the client connected to
#        >qos    Client connection TOS/DSCP value set by Squid
#        >nfmark Client connection netfilter packet MARK set by Squid
# La    local listening ip address the client connection was connected to.
# Lp    local listening port number the client connection was connected to.
# <a    server ip address of the last server or peer connection
#        <a    Server FQDN or peer name
#        <p    Server port number of the last server or peer connection
#        <la    Local IP address of the last server or peer connection
#        <lp     Local port number of the last server or peer connection
#        <qos    Server connection TOS/DSCP value set by Squid
#        <nfmark Server connection netfilter packet MARK set by Squid
# >handshake raw client handshake
# Initial client bytes received by squid on a newly
# Accepted tcp connection or inside a just established
# Connect tunnel. squid stops accumulating handshake
# Bytes as soon as the handshake parser succeeds or
# Fails (determining whether the client is using the
# Expected protocol).
# For http clients, the handshake is the request line.
# For tls clients, the handshake consists of all tls
# Records up to and including the tls record that
# Contains the last byte of the first clienthello
# Message. for clients using an unsupported protocol,
# This field contains the bytes received by squid at the
# Time of the handshake parsing failure.
# See the on_unsupported_protocol directive for more
# Information on squid handshake traffic expectations.
# Current support is limited to these contexts:
#            - http_port connections, but only when the
# On_unsupported_protocol directive is in use.
#            - https_port connections (and CONNECT tunnels) that
# Are subject to the ssl_bump peek or stare action.
# To protect binary handshake data, this field is always
# Base64-encoded (rfc 4648 section 4). if logformat
# Field encoding is configured, that encoding is applied
# On top of base64. otherwise, the computed base64 value
# Is recorded as is.
# Time related format codes:
# Ts    seconds since epoch
# Tu    subsecond time (milliseconds)
# Tl    local time. optional strftime format argument
# Default %d/%b/%y:%h:%m:%s %z
# Tg    gmt time. optional strftime format argument
# Default %d/%b/%y:%h:%m:%s %z
# Tr    response time (milliseconds)
# Dt    total time spent making dns lookups (milliseconds)
# Ts    approximate master transaction start time in
#            <full seconds since epoch>.<fractional seconds> format.
# Currently, squid considers the master transaction
# Started when a complete http request header initiating
# The transaction is received from the client. this is
# The same value that squid uses to calculate transaction
# Response time when logging %tr to access.log. currently,
# Squid uses millisecond resolution for %ts values,
# Similar to the default access.log "current time" field
#            (%ts.%03tu).
# Access control related format codes:
# Et    tag returned by external acl
# Ea    log string returned by external acl
# Un    user name (any available)
# Ul    user name from authentication
# Ue    user name from external acl helper
# Ui    user name from ident
# Un    a user name. expands to the first available name
# From the following list of information sources:
#            - authenticated user name, like %ul
#            - user name supplied by an external ACL, like %ue
#            - ssl client name, like %us
#            - ident user name, like %ui
# Credentials client credentials. the exact meaning depends on
# The authentication scheme: for basic authentication,
# It is the password; for digest, the realm sent by the
# Client; for ntlm and negotiate, the client challenge
# Or client credentials prefixed with "yr " or "kk ".
# Http related format codes:
# Request
# [http::]rm    request method (get/post etc)
#        [http::]>rm    Request method from client
#        [http::]<rm    Request method sent to server or peer
# [http::]ru    request url received (or computed) and sanitized
# Logs request uri received from the client, a
# Request adaptation service, or a request
# Redirector (whichever was applied last).
# Computed urls are uris of internally generated
# Requests and various "error:..." uris.
# Honors strip_query_terms and uri_whitespace.
# This field is not encoded by default. encoding
# This field using variants of %-encoding will
# Clash with uri_whitespace modifications that
# Also use %-encoding.
# [http::]>ru    request url received from the client (or computed)
# Computed urls are uris of internally generated
# Requests and various "error:..." uris.
# Unlike %ru, this request uri is not affected
# By request adaptation, url rewriting services,
# And strip_query_terms.
# Honors uri_whitespace.
# This field is using pass-through url encoding
# By default. encoding this field using other
# Variants of %-encoding will clash with
# Uri_whitespace modifications that also use
#                %-encoding.
# [http::]<ru    request url sent to server or peer
#        [http::]>rs    Request URL scheme from client
#        [http::]<rs    Request URL scheme sent to server or peer
#        [http::]>rd    Request URL domain from client
#        [http::]<rd    Request URL domain sent to server or peer
#        [http::]>rP    Request URL port from client
#        [http::]<rP    Request URL port sent to server or peer
#        [http::]rp    Request URL path excluding hostname
#        [http::]>rp    Request URL path excluding hostname from client
#        [http::]<rp    Request URL path excluding hostname sent to server or peer
#        [http::]rv    Request protocol version
#        [http::]>rv    Request protocol version from client
#        [http::]<rv    Request protocol version sent to server or peer
# [http::]>h    original received request header.
# Usually differs from the request header sent by
# Squid, although most fields are often preserved.
# Accepts optional header field name/value filter
# Argument using name[:[separator]element] format.
#        [http::]>ha    Received request header after adaptation and
# Redirection (pre-cache reqmod vectoring point).
# Usually differs from the request header sent by
# Squid, although most fields are often preserved.
# Optional header name argument as for >h
# Response
# [http::]<hs    http status code received from the next hop
#        [http::]>Hs    HTTP status code sent to the client
# [http::]<h    reply header. optional header name argument
# As for >h
# [http::]mt    mime content type
# Size counters
# [http::]st    total size of request + reply traffic with client
#        [http::]>st    Total size of request received from client.
# Excluding chunked encoding bytes.
#        [http::]<st    Total size of reply sent to client (after adaptation)
# [http::]>sh    size of request headers received from client
#        [http::]<sh    Size of reply headers sent to client (after adaptation)
# [http::]<sh    reply high offset sent
#        [http::]<sS    Upstream object size
# [http::]<bs    number of http-equivalent message body bytes
# Received from the next hop, excluding chunked
# Transfer encoding and control messages.
# Generated ftp/gopher listings are treated as
# Received bodies.
# Timing
# [http::]<pt    peer response time in milliseconds. the timer starts
# When the last request byte is sent to the next hop
# And stops when the last response byte is received.
#        [http::]<tt    Total time in milliseconds. The timer
# Starts with the first connect request (or write i/o)
# Sent to the first selected peer. the timer stops
# With the last i/o with the last peer.
# Squid handling related format codes:
# Ss    squid request status (tcp_miss etc)
# Sh    squid hierarchy status (default_parent etc)
# Ssl-related format codes:
# Ssl::bump_mode    sslbump decision for the transaction:
# For connect requests that initiated bumping of
# A connection and for any request received on
# An already bumped connection, squid logs the
# Corresponding sslbump mode ("splice", "bump",
#                "peek", "stare", "terminate", "server-first"
# Or "client-first"). see the ssl_bump option
# For more information about these modes.
# A "none" token is logged for requests that
# Triggered "ssl_bump" acl evaluation matching
# A "none" rule.
# In all other cases, a single dash ("-") is
# Logged.
# Ssl::>sni    ssl client sni sent to squid.
# Ssl::>cert_subject
# The subject field of the received client
# Ssl certificate or a dash ('-') if squid has
# Received an invalid/malformed certificate or
# No certificate at all. consider encoding the
# Logged value because subject often has spaces.
# Ssl::>cert_issuer
# The issuer field of the received client
# Ssl certificate or a dash ('-') if squid has
# Received an invalid/malformed certificate or
# No certificate at all. consider encoding the
# Logged value because issuer often has spaces.
# Ssl::<cert_subject
# The subject field of the received server
# Tls certificate or a dash ('-') if this is
# Not available. consider encoding the logged
# Value because subject often has spaces.
# Ssl::<cert_issuer
# The issuer field of the received server
# Tls certificate or a dash ('-') if this is
# Not available. consider encoding the logged
# Value because issuer often has spaces.
# Ssl::<cert
# The received server x509 certificate in pem
# Format, including begin and end lines (or a
# Dash ('-') if the certificate is unavailable).
# Warning: large certificates will exceed the
# Current 8kb access.log record limit, resulting
# In truncated records. such truncation usually
# Happens in the middle of a record field. the
# Limit applies to all access logging modules.
# The logged certificate may have failed
# Validation and may not be trusted by squid.
# This field does not include any intermediate
# Certificates that may have been received from
# The server or fetched during certificate
# Validation process.
# Currently, squid only collects server
# Certificates during step3 of sslbump
# Processing; connections that were not subject
# To ssl_bump rules or that did not match a peek
# Or stare rule at step2 will not have the
# Server certificate information.
# This field is using pass-through url encoding
# By default.
# Ssl::<cert_errors
# The list of certificate validation errors
# Detected by squid (including openssl and
# Certificate validation helper components). the
# Errors are listed in the discovery order. by
# Default, the error codes are separated by ':'.
# Accepts an optional separator argument.
# %ssl::>negotiated_version the negotiated tls version of the
# Client connection.
# %ssl::<negotiated_version the negotiated tls version of the
# Last server or peer connection.
# %ssl::>received_hello_version the tls version of the hello
# Message received from tls client.
# %ssl::<received_hello_version the tls version of the hello
# Message received from tls server.
# %ssl::>received_supported_version the maximum tls version
# Supported by the tls client.
# %ssl::<received_supported_version the maximum tls version
# Supported by the tls server.
# %ssl::>negotiated_cipher the negotiated cipher of the
# Client connection.
# %ssl::<negotiated_cipher the negotiated cipher of the
# Last server or peer connection.
# If icap is enabled, the following code becomes available (as
# Well as icap log codes documented with the icap_log option):
# Icap::tt        total icap processing time for the http
# Transaction. the timer ticks when icap
# Acls are checked and when icap
# Transaction is in progress.
# If adaptation is enabled the following codes become available:
# Adapt::<last_h    the header of the last icap response or
# Meta-information from the last ecap
# Transaction related to the http transaction.
# Like <h, accepts an optional header name
# Argument.
# Adapt::sum_trs summed adaptation transaction response
# Times recorded as a comma-separated list in
# The order of transaction start time. each time
# Value is recorded as an integer number,
# Representing response time of one or more
# Adaptation (icap or ecap) transaction in
# Milliseconds.  when a failed transaction is
# Being retried or repeated, its time is not
# Logged individually but added to the
# Replacement (next) transaction. see also:
# Adapt::all_trs.
# Adapt::all_trs all adaptation transaction response times.
# Same as adaptation_strs but response times of
# Individual transactions are never added
# Together. instead, all transaction response
# Times are recorded individually.
# You can prefix adapt::*_trs format codes with adaptation
# Service name in curly braces to record response time(s) specific
# To that service. for example: %{my_service}adapt::sum_trs
# Format codes related to the proxy protocol:
# Proxy_protocol::>h proxy protocol header, including optional tlvs.
# Supports the same field and element reporting/extraction logic
# As %http::>h. for configuration and reporting purposes, squid
# Maps each proxy tlv to an http header field: the tlv type
#                (configured as a decimal integer) is the field name, and the
# Tlv value is the field value. all tlvs of "local" connections
#                (in PROXY protocol terminology) are currently skipped/ignored.
# Squid also maps the following standard proxy protocol header
# Blocks to pseudo http headers (their names use proxy
# Terminology and start with a colon, following http tradition
# For pseudo headers): :command, :version, :src_addr, :dst_addr,
#                :src_port, and :dst_port.
# Without optional parameters, this logformat code logs
# Pseudo headers and tlvs.
# This format code uses pass-through url encoding by default.
# Example:
#                    # Relay custom PROXY TLV #224 to adaptation services
# Adaptation_meta client-foo "%proxy_protocol::>h{224}
# See also: %http::>h
# The default formats available (which do not need re-defining) are:
#Logformat squid      %ts.%03tu %6tr %>a %Ss/%03>Hs %<st %rm %ru %[un %Sh/%<a %mt
#Logformat common     %>a %[ui %[un [%tl] "%rm %ru HTTP/%rv" %>Hs %<st %Ss:%Sh
#Logformat combined   %>a %[ui %[un [%tl] "%rm %ru HTTP/%rv" %>Hs %<st "%{Referer}>h" "%{User-Agent}>h" %Ss:%Sh
#Logformat referrer   %ts.%03tu %>a %{Referer}>h %ru
#Logformat useragent  %>a [%tl] "%{User-Agent}>h"
# Note: when the log_mime_hdrs directive is set to on.
# The squid, common and combined formats have a safely encoded copy
# Of the mime headers appended to each line within a pair of brackets.
# Note: the common and combined formats are not quite true to the apache definition.
# The logs from squid contain an extra status and hierarchy code appended.
#Default:
# The format definitions squid, common, combined, referrer, useragent are built in.

# Tag: access_log
# Configures whether and how squid logs http and icp transactions.
# If access logging is enabled, a single line is logged for every
# Matching http or icp request. the recommended directive formats are:
# Access_log <module>:<place> [option ...] [acl acl ...]
# Access_log none [acl acl ...]
# The following directive format is accepted but may be deprecated:
# Access_log <module>:<place> [<logformat name> [acl acl ...]]
# In most cases, the first acl name must not contain the '=' character
# And should not be equal to an existing logformat name. you can always
# Start with an 'all' acl to work around those restrictions.
# Will log to the specified module:place using the specified format (which
# Must be defined in a logformat directive) those entries which match
# All the acl's specified (which must be defined in acl clauses).
# If no acl is specified, all requests will be logged to this destination.
# ===== available options for the recommended directive format =====
# Logformat=name        names log line format (either built-in or
# Defined by a logformat directive). defaults
# To 'squid'.
# Buffer-size=64kb    defines approximate buffering limit for log
# Records (see buffered_logs).  squid should not
# Keep more than the specified size and, hence,
# Should flush records before the buffer becomes
# Full to avoid overflows under normal
# Conditions (the exact flushing algorithm is
# Module-dependent though).  the on-error option
# Controls overflow handling.
# On-error=die|drop    defines action on unrecoverable errors. the
#                'drop' action ignores (i.e., does not log)
# Affected log records. the default 'die' action
# Kills the affected worker. the drop action
# Support has not been tested for modules other
# Than tcp.
# Rotate=n        specifies the number of log file rotations to
# Make when you run 'squid -k rotate'. the default
# Is to obey the logfile_rotate directive. setting
# Rotate=0 will disable the file name rotation,
# But the log files are still closed and re-opened.
# This will enable you to rename the logfiles
# Yourself just before sending the rotate signal.
# Only supported by the stdio module.
# ===== modules currently available =====
# None    do not log any requests matching these acl.
# Do not specify place or logformat name.
# Stdio    write each log line to disk immediately at the completion of
# Each request.
# Place: the filename and path to be written.
# Daemon    very similar to stdio. but instead of writing to disk the log
# Line is passed to a daemon helper for asychronous handling instead.
# Place: varies depending on the daemon.
# Log_file_daemon place: the file name and path to be written.
# Syslog    to log each request via syslog facility.
# Place: the syslog facility and priority level for these entries.
# Place format:  facility.priority
# Where facility could be any of:
# Authpriv, daemon, local0 ... local7 or user.
# And priority could be any of:
# Err, warning, notice, info, debug.
# Udp    to send each log line as text data to a udp receiver.
# Place: the destination host name or ip and port.
# Place format:   //host:port
# Tcp    to send each log line as text data to a tcp receiver.
# Lines may be accumulated before sending (see buffered_logs).
# Place: the destination host name or ip and port.
# Place format:   //host:port
# Default:
# Access_log daemon:/var/log/squid/access.log squid
#Default:
# Access_log daemon:/var/log/squid/access.log squid

# Tag: icap_log
# Icap log files record icap transaction summaries, one line per
# Transaction.
# The icap_log option format is:
# Icap_log <filepath> [<logformat name> [acl acl ...]]
# Icap_log none [acl acl ...]]
# Please see access_log option documentation for details. the two
# Kinds of logs share the overall configuration approach and many
# Features.
# Icap processing of a single http message or transaction may
# Require multiple icap transactions.  in such cases, multiple
# Icap transaction log lines will correspond to a single access
# Log line.
# Icap log supports many access.log logformat %codes. in icap context,
# Http message-related %codes are applied to the http message embedded
# In an icap message. logformat "%http::>..." codes are used for http
# Messages embedded in icap requests while "%http::<..." codes are used
# For http messages embedded in icap responses. for example:
# Http::>h    to-be-adapted http message headers sent by squid to
# The icap service. for reqmod transactions, these are
# Http request headers. for respmod, these are http
# Response headers, but squid currently cannot log them
#                (i.e., %http::>h will expand to "-" for RESPMOD).
# Http::<h    adapted http message headers sent by the icap
# Service to squid (i.e., http request headers in regular
# Reqmod; http response headers in respmod and during
# Request satisfaction in reqmod).
# Icap options transactions do not embed http messages.
# Several logformat codes below deal with icap message bodies. an icap
# Message body, if any, typically includes a complete http message
#    (required HTTP headers plus optional HTTP message body). When
# Computing http message body size for these logformat codes, squid
# Either includes or excludes chunked encoding overheads; see
# Code-specific documentation for details.
# For secure icap services, all size-related information is currently
# Computed before/after tls encryption/decryption, as if tls was not
# In use at all.
# The following format codes are also available for icap logs:
# Icap::<a    icap server ip address. similar to <a.
# Icap::<service_name    icap service name from the icap_service
# Option in squid configuration file.
# Icap::ru    icap request-uri. similar to ru.
# Icap::rm    icap request method (reqmod, respmod, or
# Options). similar to existing rm.
# Icap::>st    the total size of the icap request sent to the icap
# Server (icap headers + icap body), including chunking
# Metadata (if any).
# Icap::<st    the total size of the icap response received from the
# Icap server (icap headers + icap body), including
# Chunking metadata (if any).
# Icap::<bs    the size of the icap response body received from the
# Icap server, excluding chunking metadata (if any).
# Icap::tr     transaction response time (in
# Milliseconds).  the timer starts when
# The icap transaction is created and
# Stops when the transaction is completed.
# Similar to tr.
# Icap::tio    transaction i/o time (in milliseconds). the
# Timer starts when the first icap request
# Byte is scheduled for sending. the timers
# Stops when the last byte of the icap response
# Is received.
# Icap::to     transaction outcome: icap_err* for all
# Transaction errors, icap_opt for option
# Transactions, icap_echo for 204
# Responses, icap_mod for message
# Modification, and icap_sat for request
# Satisfaction. similar to ss.
# Icap::hs    icap response status code. similar to hs.
# Icap::>h    icap request header(s). similar to >h.
# Icap::<h    icap response header(s). similar to <h.
# The default icap log format, which can be used without an explicit
# Definition, is called icap_squid:
#Logformat icap_squid %ts.%03tu %6icap::tr %>A %icap::to/%03icap::Hs %icap::<st %icap::rm %icap::ru %un -/%icap::<A -
# See also: logformat and %adapt::<last_h
#Default:
# None

# Tag: logfile_daemon
# Specify the path to the logfile-writing daemon. this daemon is
# Used to write the access and store logs, if configured.
# Squid sends a number of commands to the log daemon:
# L<data>\n - logfile data
# R\n - rotate file
# T\n - truncate file
# O\n - reopen file
# F\n - flush file
# R<n>\n - set rotate count to <n>
# B<n>\n - 1 = buffer output, 0 = don't buffer output
# No responses is expected.
#Default:
# Logfile_daemon /usr/lib/squid/log_file_daemon

# Tag: stats_collection    allow|deny acl acl...
# This options allows you to control which requests gets accounted
# In performance counters.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Allow logging for all transactions.

# Tag: cache_store_log
# Logs the activities of the storage manager.  shows which
# Objects are ejected from the cache, and which objects are
# Saved and for how long.
# There are not really utilities to analyze this data, so you can safely
# Disable it (the default).
# Store log uses modular logging outputs. see access_log for the list
# Of modules supported.
# Example:
# Cache_store_log stdio:/var/log/squid/store.log
# Cache_store_log daemon:/var/log/squid/store.log
#Default:
# None

# Tag: cache_swap_state
# Location for the cache "swap.state" file. this index file holds
# The metadata of objects saved on disk.  it is used to rebuild
# The cache during startup.  normally this file resides in each
#    'cache_dir' directory, but you may specify an alternate
# Pathname here.  note you must give a full filename, not just
# A directory. since this is the index for the whole object
# List you cannot periodically rotate it!
# If %s can be used in the file name it will be replaced with a
# A representation of the cache_dir name where each / is replaced
# With '.'. this is needed to allow adding/removing cache_dir
# Lines when cache_swap_log is being used.
# If have more than one 'cache_dir', and %s is not used in the name
# These swap logs will have names such as:
# Cache_swap_log.00
# Cache_swap_log.01
# Cache_swap_log.02
# The numbered extension (which is added automatically)
# Corresponds to the order of the 'cache_dir' lines in this
# Configuration file.  if you change the order of the 'cache_dir'
# Lines in this file, these index files will not correspond to
# The correct 'cache_dir' entry (unless you manually rename
# Them).  we recommend you do not use this option.  it is
# Better to keep these index files in each 'cache_dir' directory.
#Default:
# Store the journal inside its cache_dir

# Tag: logfile_rotate
# Specifies the default number of logfile rotations to make when you
# Type 'squid -k rotate'. the default is 10, which will rotate
# With extensions 0 through 9. setting logfile_rotate to 0 will
# Disable the file name rotation, but the logfiles are still closed
# And re-opened. this will enable you to rename the logfiles
# Yourself just before sending the rotate signal.
# Note, from squid-3.1 this option is only a default for cache.log,
# That log can be rotated separately by using debug_options.
# Note, from squid-4 this option is only a default for access.log
# Recorded by stdio: module. those logs can be rotated separately by
# Using the rotate=n option on their access_log directive.
# Note, the 'squid -k rotate' command normally sends a usr1
# Signal to the running squid process.  in certain situations
#    (e.g. on Linux with Async I/O), USR1 is used for other
# Purposes, so -k rotate uses another signal.  it is best to get
# In the habit of using 'squid -k rotate' instead of 'kill -usr1
#    <pid>'.
# Note, for debian/linux the default of logfile_rotate is
# Zero, since it includes external logfile-rotation methods.
#Default:
# Logfile_rotate 0

# Tag: mime_table
# Path to squid's icon configuration file.
# You shouldn't need to change this, but the default file contains
# Examples and formatting information if you do.
#Default:
# Mime_table /usr/share/squid/mime.conf

# Tag: log_mime_hdrs    on|off
# The cache can record both the request and the response mime
# Headers for each http transaction.  the headers are encoded
# Safely and will appear as two bracketed fields at the end of
# The access log (for either the native or httpd-emulated log
# Formats).  to enable this logging set log_mime_hdrs to 'on'.
#Default:
# Log_mime_hdrs off

# Tag: pid_filename
# A filename to write the process-id to.  to disable, enter "none".
#Default:
# Pid_filename /run/squid.pid

# Tag: client_netmask
# A netmask for client addresses in logfiles and cachemgr output.
# Change this to protect the privacy of your cache clients.
# A netmask of 255.255.255.0 will log all ip's in that range with
# The last digit set to '0'.
#Default:
# Log full client ip address

# Tag: strip_query_terms
# By default, squid strips query terms from requested urls before
# Logging.  this protects your user's privacy and reduces log size.
# When investigating hit/miss or other caching behaviour you
# Will need to disable this to see the full url used by squid.
#Default:
# Strip_query_terms on

# Tag: buffered_logs    on|off
# Whether to write/send access_log records asap or accumulate them and
# Then write/send them in larger chunks. buffering may improve
# Performance because it decreases the number of i/os. however,
# Buffering increases the delay before log records become available to
# The final recipient (e.g., a disk file or logging daemon) and,
# Hence, increases the risk of log records loss.
# Note that even when buffered_logs are off, squid may have to buffer
# Records if it cannot write/send them immediately due to pending i/os
#    (e.g., the I/O writing the previous log record) or connectivity loss.
# Currently honored by 'daemon' and 'tcp' access_log modules only.
#Default:
# Buffered_logs off

# Tag: netdb_filename
# Where squid stores it's netdb journal.
# When enabled this journal preserves netdb state between restarts.
# To disable, enter "none".
#Default:
# Netdb_filename stdio:/var/spool/squid/netdb.state

# Options for troubleshooting
# -----------------------------------------------------------------------------

# Tag: cache_log
# Squid administrative logging file.
# This is where general information about squid behavior goes. you can
# Increase the amount of data logged to this file and how often it is
# Rotated with "debug_options"
#Default:
# Cache_log /var/log/squid/cache.log

# Tag: debug_options
# Logging options are set as section,level where each source file
# Is assigned a unique section.  lower levels result in less
# Output,  full debugging (level 9) can result in a very large
# Log file, so be careful.
# The magic word "all" sets debugging levels for all sections.
# The default is to run with "all,1" to record important warnings.
# The rotate=n option can be used to keep more or less of these logs
# Than would otherwise be kept by logfile_rotate.
# For most uses a single log should be enough to monitor current
# Events affecting squid.
#Default:
# Log all critical and important messages.

# Tag: coredump_dir
# By default squid leaves core files in the directory from where
# It was started. if you set 'coredump_dir' to a directory
# That exists, squid will chdir() to that directory at startup
# And coredump files will be left there.
#Default:
# Use the directory from where squid was started.

# Leave coredumps in the first cache dir
coredump_dir /var/spool/squid

# Options for ftp gatewaying
# -----------------------------------------------------------------------------

# Tag: ftp_user
# If you want the anonymous login password to be more informative
#    (and enable the use of picky FTP servers), set this to something
# Reasonable for your domain, like wwwuser@somewhere.net
# The reason why this is domainless by default is the
# Request can be made on the behalf of a user in any domain,
# Depending on how the cache is used.
# Some ftp server also validate the email address is valid
#    (for example perl.com).
#Default:
# Ftp_user squid@

# Tag: ftp_passive
# If your firewall does not allow squid to use passive
# Connections, turn off this option.
# Use of ftp_epsv_all option requires this to be on.
#Default:
# Ftp_passive on

# Tag: ftp_epsv_all
# Ftp protocol extensions permit the use of a special "epsv all" command.
# Nats may be able to put the connection on a "fast path" through the
# Translator, as the eprt command will never be used and therefore,
# Translation of the data portion of the segments will never be needed.
# When a client only expects to do two-way ftp transfers this may be
# Useful.
# If squid finds that it must do a three-way ftp transfer after issuing
# An epsv all command, the ftp session will fail.
# If you have any doubts about this option do not use it.
# Squid will nicely attempt all other connection methods.
# Requires ftp_passive to be on (default) for any effect.
#Default:
# Ftp_epsv_all off

# Tag: ftp_epsv
# Ftp protocol extensions permit the use of a special "epsv" command.
# Nats may be able to put the connection on a "fast path" through the
# Translator using epsv, as the eprt command will never be used
# And therefore, translation of the data portion of the segments
# Will never be needed.
# Epsv is often required to interoperate with ftp servers on ipv6
# Networks. on the other hand, it may break some ipv4 servers.
# By default, epsv may try epsv with any ftp server. to fine tune
# That decision, you may restrict epsv to certain clients or servers
# Using acls:
# Ftp_epsv allow|deny al1 acl2 ...
# Warning: disabling epsv may cause problems with external nat and ipv6.
# Only fast acls are supported.
# Requires ftp_passive to be on (default) for any effect.
#Default:
# None

# Tag: ftp_eprt
# Ftp protocol extensions permit the use of a special "eprt" command.
# This extension provides a protocol neutral alternative to the
# Ipv4-only port command. when supported it enables active ftp data
# Channels over ipv6 and efficient nat handling.
# Turning this off will prevent eprt being attempted and will skip
# Straight to using port for ipv4 servers.
# Some devices are known to not handle this extension correctly and
# May result in crashes. devices which suport eprt enough to fail
# Cleanly will result in squid attempting port anyway. this directive
# Should only be disabled when eprt results in device failures.
# Warning: doing so will convert squid back to the old behavior with all
# The related problems with external nat devices/layers and ipv4-only ftp.
#Default:
# Ftp_eprt on

# Tag: ftp_sanitycheck
# For security and data integrity reasons squid by default performs
# Sanity checks of the addresses of ftp data connections ensure the
# Data connection is to the requested server. if you need to allow
# Ftp connections to servers using another ip address for the data
# Connection turn this off.
#Default:
# Ftp_sanitycheck on

# Tag: ftp_telnet_protocol
# The ftp protocol is officially defined to use the telnet protocol
# As transport channel for the control connection. however, many
# Implementations are broken and does not respect this aspect of
# The ftp protocol.
# If you have trouble accessing files with ascii code 255 in the
# Path or similar problems involving this ascii code you can
# Try setting this directive to off. if that helps, report to the
# Operator of the ftp server in question that their ftp server
# Is broken and does not follow the ftp standard.
#Default:
# Ftp_telnet_protocol on

# Options for external support programs
# -----------------------------------------------------------------------------

# Tag: diskd_program
# Specify the location of the diskd executable.
# Note this is only useful if you have compiled in
# Diskd as one of the store io modules.
#Default:
# Diskd_program /usr/lib/squid/diskd

# Tag: unlinkd_program
# Specify the location of the executable for file deletion process.
#Default:
# Unlinkd_program /usr/lib/squid/unlinkd

# Tag: pinger_program
# Specify the location of the executable for the pinger process.
#Default:
# Pinger_program /usr/lib/squid/pinger

# Tag: pinger_enable
# Control whether the pinger is active at run-time.
# Enables turning icmp pinger on and off with a simple
# Squid -k reconfigure.
#Default:
# Pinger_enable on

# Options for url rewriting
# -----------------------------------------------------------------------------

# Tag: url_rewrite_program
# The name and command line parameters of an admin-provided executable
# For redirecting clients or adjusting/replacing client request urls.
# This helper is consulted after the received request is cleared by
# Http_access and adapted using eicap/icap services (if any). if the
# Helper does not redirect the client, squid checks adapted_http_access
# And may consult the cache or forward the request to the next hop.
# For each request, the helper gets one line in the following format:
# [channel-id <sp>] request-url [<sp> extras] <nl>
# Use url_rewrite_extras to configure what squid sends as 'extras'.
# The helper must reply to each query using a single line:
# [channel-id <sp>] result [<sp> kv-pairs] <nl>
# The result section must match exactly one of the following outcomes:
# Ok [status=30n] url="..."
# Redirect the client to a url supplied in the 'url' parameter.
# Optional 'status' specifies the status code to send to the
# Client in squid's http redirect response. it must be one of
# The standard http redirect status codes: 301, 302, 303, 307,
# Or 308. when no specific status is requested, squid uses 302.
# Ok rewrite-url="..."
# Replace the current request url with the one supplied in the
#        'rewrite-url' parameter. Squid fetches the resource specified
# By the new url and forwards the received response (or its
# Cached copy) to the client.
# Warning: avoid rewriting urls! when possible, redirect the
# Client using an "ok url=..." helper response instead.
# Rewriting urls may create inconsistent requests and/or break
# Synchronization between internal client and origin server
# States, especially when urls or other message parts contain
# Snippets of that state. for example, squid does not adjust
# Location headers and embedded urls after the helper rewrites
# The request url.
# Ok
# Keep the client request intact.
# Err
# Keep the client request intact.
# Bh [message="..."]
# A helper problem that should be reported to the squid admin
# Via a level-1 cache.log message. the 'message' parameter is
# Reserved for specifying the log message.
# In addition to the kv-pairs mentioned above, squid also understands
# The following optional kv-pairs in url rewriter responses:
# Clt_conn_tag=tag
# Associates a tag with the client tcp connection.
# The clt_conn_tag=tag pair is treated as a regular transaction
# Annotation for the current request and also annotates future
# Requests on the same client connection. a helper may update
# The tag during subsequent requests by returning a new kv-pair.
# Helper messages contain the channel-id part if and only if the
# Url_rewrite_children directive specifies positive concurrency. as a
# Channel-id value, squid sends a number between 0 and concurrency-1.
# The helper must echo back the received channel-id in its response.
# By default, squid does not use a url rewriter.
#Default:
# None

# Tag: url_rewrite_children
# Specifies the maximum number of redirector processes that squid may
# Spawn (numberofchildren) and several related options. using too few of
# These helper processes (a.k.a. "helpers") creates request queues.
# Using too many helpers wastes your system resources.
# Usage: numberofchildren [option]...
# The startup= and idle= options allow some measure of skew in your
# Tuning.
# Startup=
# Sets a minimum of how many processes are to be spawned when squid
# Starts or reconfigures. when set to zero the first request will
# Cause spawning of the first child process to handle it.
# Starting too few will cause an initial slowdown in traffic as squid
# Attempts to simultaneously spawn enough processes to cope.
# Idle=
# Sets a minimum of how many processes squid is to try and keep available
# At all times. when traffic begins to rise above what the existing
# Processes can handle this many more will be spawned up to the maximum
# Configured. a minimum setting of 1 is required.
# Concurrency=
# The number of requests each redirector helper can handle in
# Parallel. defaults to 0 which indicates the redirector
# Is a old-style single threaded redirector.
# When this directive is set to a value >= 1 then the protocol
# Used to communicate with the helper is modified to include
# An id in front of the request/response. the id from the request
# Must be echoed back with the response to that request.
# Queue-size=n
# Sets the maximum number of queued requests. a request is queued when
# No existing child can accept it due to concurrency limit and no new
# Child can be started due to numberofchildren limit. the default
# Maximum is zero if url_rewrite_bypass is enabled and
# 2*numberofchildren otherwise. if the queued requests exceed queue size
# And redirector_bypass configuration option is set, then redirector is
# Bypassed. otherwise, squid is allowed to temporarily exceed the
# Configured maximum, marking the affected helper as "overloaded". if
# The helper overload lasts more than 3 minutes, the action prescribed
# By the on-persistent-overload option applies.
# On-persistent-overload=action
# Specifies squid reaction to a new helper request arriving when the helper
# Has been overloaded for more that 3 minutes already. the number of queued
# Requests determines whether the helper is overloaded (see the queue-size
# Option).
# Two actions are supported:
# Die    squid worker quits. this is the default behavior.
# Err    squid treats the helper request as if it was
# Immediately submitted, and the helper immediately
# Replied with an err response. this action has no effect
# On the already queued and in-progress helper requests.
#Default:
# Url_rewrite_children 20 startup=0 idle=1 concurrency=0

# Tag: url_rewrite_host_header
# To preserve same-origin security policies in browsers and
# Prevent host: header forgery by redirectors squid rewrites
# Any host: header in redirected requests.
# If you are running an accelerator this may not be a wanted
# Effect of a redirector. this directive enables you disable
# Host: alteration in reverse-proxy traffic.
# Warning: entries are cached on the result of the url rewriting
# Process, so be careful if you have domain-virtual hosts.
# Warning: squid and other software verifies the url and host
# Are matching, so be careful not to relay through other proxies
# Or inspecting firewalls with this disabled.
#Default:
# Url_rewrite_host_header on

# Tag: url_rewrite_access
# If defined, this access list specifies which requests are
# Sent to the redirector processes.
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Allow, unless rules exist in squid.conf.

# Tag: url_rewrite_bypass
# When this is 'on', a request will not go through the
# Redirector if all the helpers are busy. if this is 'off' and the
# Redirector queue grows too large, the action is prescribed by the
# On-persistent-overload option. you should only enable this if the
# Redirectors are not critical to your caching system. if you use
# Redirectors for access control, and you enable this option,
# Users may have access to pages they should not
# Be allowed to request.
# Enabling this option sets the default url_rewrite_children queue-size
# Option value to 0.
#Default:
# Url_rewrite_bypass off

# Tag: url_rewrite_extras
# Specifies a string to be append to request line format for the
# Rewriter helper. "quoted" format values may contain spaces and
# Logformat %macros. in theory, any logformat %macro can be used.
# In practice, a %macro expands as a dash (-) if the helper request is
# Sent before the required macro information is available to squid.
#Default:
# Url_rewrite_extras "%>a/%>a %un %>rm myip=%la myport=%lp"

# Tag: url_rewrite_timeout
# Squid times active requests to redirector. the timeout value and squid
# Reaction to a timed out request are configurable using the following
# Format:
# Url_rewrite_timeout timeout time-units on_timeout=<action> [response=<quoted-response>]
# Supported timeout actions:
# Fail    squid return a err_gateway_failure error page
# Bypass    do not re-write the url
# Retry    send the lookup to the helper again
# Use_configured_response
# Use the <quoted-response> as helper response
#Default:
# Squid waits for the helper response forever

# Options for store id
# -----------------------------------------------------------------------------

# Tag: store_id_program
# Specify the location of the executable storeid helper to use.
# Since they can perform almost any function there isn't one included.
# For each requested url, the helper will receive one line with the format
# [channel-id <sp>] url [<sp> extras]<nl>
# After processing the request the helper must reply using the following format:
# [channel-id <sp>] result [<sp> kv-pairs]
# The result code can be:
# Ok store-id="..."
# Use the storeid supplied in 'store-id='.
# Err
# The default is to use http request url as the store id.
# Bh
# An internal error occurred in the helper, preventing
# A result being identified.
# In addition to the above kv-pairs squid also understands the following
# Optional kv-pairs received from url rewriters:
# Clt_conn_tag=tag
# Associates a tag with the client tcp connection.
# Please see url_rewrite_program related documentation for this
# Kv-pair
# Helper programs should be prepared to receive and possibly ignore
# Additional whitespace-separated tokens on each input line.
# When using the concurrency= option the protocol is changed by
# Introducing a query channel tag in front of the request/response.
# The query channel tag is a number between 0 and concurrency-1.
# This value must be echoed back unchanged to squid as the first part
# Of the response relating to its request.
# Note: when using storeid refresh_pattern will apply to the storeid
# Returned from the helper and not the url.
# Warning: wrong storeid value returned by a careless helper may result
# In the wrong cached response returned to the user.
# By default, a storeid helper is not used.
#Default:
# None

# Tag: store_id_extras
# Specifies a string to be append to request line format for the
# Storeid helper. "quoted" format values may contain spaces and
# Logformat %macros. in theory, any logformat %macro can be used.
# In practice, a %macro expands as a dash (-) if the helper request is
# Sent before the required macro information is available to squid.
#Default:
# Store_id_extras "%>a/%>a %un %>rm myip=%la myport=%lp"

# Tag: store_id_children
# Specifies the maximum number of storeid helper processes that squid
# May spawn (numberofchildren) and several related options. using
# Too few of these helper processes (a.k.a. "helpers") creates request
# Queues. using too many helpers wastes your system resources.
# Usage: numberofchildren [option]...
# The startup= and idle= options allow some measure of skew in your
# Tuning.
# Startup=
# Sets a minimum of how many processes are to be spawned when squid
# Starts or reconfigures. when set to zero the first request will
# Cause spawning of the first child process to handle it.
# Starting too few will cause an initial slowdown in traffic as squid
# Attempts to simultaneously spawn enough processes to cope.
# Idle=
# Sets a minimum of how many processes squid is to try and keep available
# At all times. when traffic begins to rise above what the existing
# Processes can handle this many more will be spawned up to the maximum
# Configured. a minimum setting of 1 is required.
# Concurrency=
# The number of requests each storeid helper can handle in
# Parallel. defaults to 0 which indicates the helper
# Is a old-style single threaded program.
# When this directive is set to a value >= 1 then the protocol
# Used to communicate with the helper is modified to include
# An id in front of the request/response. the id from the request
# Must be echoed back with the response to that request.
# Queue-size=n
# Sets the maximum number of queued requests to n. a request is queued
# When no existing child can accept it due to concurrency limit and no
# New child can be started due to numberofchildren limit. the default
# Maximum is 2*numberofchildren. if the queued requests exceed queue
# Size and redirector_bypass configuration option is set, then
# Redirector is bypassed. otherwise, squid is allowed to temporarily
# Exceed the configured maximum, marking the affected helper as
#    "overloaded". If the helper overload lasts more than 3 minutes, the
# Action prescribed by the on-persistent-overload option applies.
# On-persistent-overload=action
# Specifies squid reaction to a new helper request arriving when the helper
# Has been overloaded for more that 3 minutes already. the number of queued
# Requests determines whether the helper is overloaded (see the queue-size
# Option).
# Two actions are supported:
# Die    squid worker quits. this is the default behavior.
# Err    squid treats the helper request as if it was
# Immediately submitted, and the helper immediately
# Replied with an err response. this action has no effect
# On the already queued and in-progress helper requests.
#Default:
# Store_id_children 20 startup=0 idle=1 concurrency=0

# Tag: store_id_access
# If defined, this access list specifies which requests are
# Sent to the storeid processes.  by default all requests
# Are sent.
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Allow, unless rules exist in squid.conf.

# Tag: store_id_bypass
# When this is 'on', a request will not go through the
# Helper if all helpers are busy. if this is 'off' and the helper
# Queue grows too large, the action is prescribed by the
# On-persistent-overload option. you should only enable this if the
# Helpers are not critical to your caching system. if you use
# Helpers for critical caching components, and you enable this
# Option,    users may not get objects from cache.
# This options sets default queue-size option of the store_id_children
# To 0.
#Default:
# Store_id_bypass on

# Options for tuning the cache
# -----------------------------------------------------------------------------

# Tag: cache
# Requests denied by this directive will not be served from the cache
# And their responses will not be stored in the cache. this directive
# Has no effect on other transactions and on already cached responses.
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# This and the two other similar caching directives listed below are
# Checked at different transaction processing stages, have different
# Access to response information, affect different cache operations,
# And differ in slow acls support:
# * cache: checked before squid makes a hit/miss determination.
# No access to reply information!
# Denies both serving a hit and storing a miss.
# Supports both fast and slow acls.
#    * send_hit: Checked after a hit was detected.
# Has access to reply (hit) information.
# Denies serving a hit only.
# Supports fast acls only.
#    * store_miss: Checked before storing a cachable miss.
# Has access to reply (miss) information.
# Denies storing a miss only.
# Supports fast acls only.
# If you are not sure which of the three directives to use, apply the
# Following decision logic:
# * if your acl(s) are of slow type _and_ need response info, redesign.
# Squid does not support that particular combination at this time.
# Otherwise:
#    * if your directive ACL(s) are of slow type, use "cache"; and/or
#    * if your directive ACL(s) need no response info, use "cache".
# Otherwise:
#    * if you do not want the response cached, use store_miss; and/or
#    * if you do not want a hit on a cached response, use send_hit.
#Default:
# By default, this directive is unused and has no effect.

# Tag: send_hit
# Responses denied by this directive will not be served from the cache
#    (but may still be cached, see store_miss). This directive has no
# Effect on the responses it allows and on the cached objects.
# Please see the "cache" directive for a summary of differences among
# Store_miss, send_hit, and cache directives.
# Unlike the "cache" directive, send_hit only supports fast acl
# Types.  see http://wiki.squid-cache.org/squidfaq/squidacl for details.
# For example:
# # Apply custom store id mapping to some urls
# Acl mapme dstdomain .c.example.com
# Store_id_program ...
# Store_id_access allow mapme
# # But prevent caching of special responses
#        # Such as 302 redirects that cause StoreID loops
# Acl ordinary http_status 200-299
# Store_miss deny mapme !ordinary
# # And do not serve any previously stored special responses
#        # From the cache (in case they were already cached before
#        # The above store_miss rule was in effect).
# Send_hit deny mapme !ordinary
#Default:
# By default, this directive is unused and has no effect.

# Tag: store_miss
# Responses denied by this directive will not be cached (but may still
# Be served from the cache, see send_hit). this directive has no
# Effect on the responses it allows and on the already cached responses.
# Please see the "cache" directive for a summary of differences among
# Store_miss, send_hit, and cache directives. see the
# Send_hit directive for a usage example.
# Unlike the "cache" directive, store_miss only supports fast acl
# Types.  see http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# By default, this directive is unused and has no effect.

# Tag: max_stale    time-units
# This option puts an upper limit on how stale content squid
# Will serve from the cache if cache validation fails.
# Can be overriden by the refresh_pattern max-stale option.
#Default:
# Max_stale 1 week

# Tag: refresh_pattern
# Usage: refresh_pattern [-i] regex min percent max [options]
# By default, regular expressions are case-sensitive.  to make
# Them case-insensitive, use the -i option.
# 'min' is the time (in minutes) an object without an explicit
# Expiry time should be considered fresh. the recommended
# Value is 0, any higher values may cause dynamic applications
# To be erroneously cached unless the application designer
# Has taken the appropriate actions.
# 'percent' is a percentage of the objects age (time since last
# Modification age) an object without explicit expiry time
# Will be considered fresh.
# 'max' is an upper limit on how long objects without an explicit
# Expiry time will be considered fresh. the value is also used
# To form cache-control: max-age header for a request sent from
# Squid to origin/parent.
# Options: override-expire
# Override-lastmod
# Reload-into-ims
# Ignore-reload
# Ignore-no-store
# Ignore-private
# Max-stale=nn
# Refresh-ims
# Store-stale
# Override-expire enforces min age even if the server
# Sent an explicit expiry time (e.g., with the
# Expires: header or cache-control: max-age). doing this
# Violates the http standard.  enabling this feature
# Could make you liable for problems which it causes.
# Note: override-expire does not enforce staleness - it only extends
# Freshness / min. if the server returns a expires time which
# Is longer than your max time, squid will still consider
# The object fresh for that period of time.
# Override-lastmod enforces min age even on objects
# That were modified recently.
# Reload-into-ims changes a client no-cache or ``reload''
# Request for a cached entry into a conditional request using
# If-modified-since and/or if-none-match headers, provided the
# Cached entry has a last-modified and/or a strong etag header.
# Doing this violates the http standard. enabling this feature
# Could make you liable for problems which it causes.
# Ignore-reload ignores a client no-cache or ``reload''
# Header. doing this violates the http standard. enabling
# This feature could make you liable for problems which
# It causes.
# Ignore-no-store ignores any ``cache-control: no-store''
# Headers received from a server. doing this violates
# The http standard. enabling this feature could make you
# Liable for problems which it causes.
# Ignore-private ignores any ``cache-control: private''
# Headers received from a server. doing this violates
# The http standard. enabling this feature could make you
# Liable for problems which it causes.
# Refresh-ims causes squid to contact the origin server
# When a client issues an if-modified-since request. this
# Ensures that the client will receive an updated version
# If one is available.
# Store-stale stores responses even if they don't have explicit
# Freshness or a validator (i.e., last-modified or an etag)
# Present, or if they're already stale. by default, squid will
# Not cache such responses because they usually can't be
# Reused. note that such responses will be stale by default.
# Max-stale=nn provide a maximum staleness factor. squid won't
# Serve objects more stale than this even if it failed to
# Validate the object. default: use the max_stale global limit.
# Basically a cached object is:
# Fresh if expire > now, else stale
# Stale if age > max
# Fresh if lm-factor < percent, else stale
# Fresh if age < min
# Else stale
# The refresh_pattern lines are checked in the order listed here.
# The first entry which matches is used.  if none of the entries
# Match the default will be used.
# Note, you must uncomment all the default lines if you want
# To change one. the default setting is only active if none is
# Used.

# Tag: quick_abort_min    (kb)
#Default:
# Quick_abort_min 16 kb

# Tag: quick_abort_max    (kb)
#Default:
# Quick_abort_max 16 kb

# Tag: quick_abort_pct    (percent)
# The cache by default continues downloading aborted requests
# Which are almost completed (less than 16 kb remaining). this
# May be undesirable on slow (e.g. slip) links and/or very busy
# Caches.  impatient users may tie up file descriptors and
# Bandwidth by repeatedly requesting and immediately aborting
# Downloads.
# When the user aborts a request, squid will check the
# Quick_abort values to the amount of data transferred until
# Then.
# If the transfer has less than 'quick_abort_min' kb remaining,
# It will finish the retrieval.
# If the transfer has more than 'quick_abort_max' kb remaining,
# It will abort the retrieval.
# If more than 'quick_abort_pct' of the transfer has completed,
# It will finish the retrieval.
# If you do not want any retrieval to continue after the client
# Has aborted, set both 'quick_abort_min' and 'quick_abort_max'
# To '0 kb'.
# If you want retrievals to always continue if they are being
# Cached set 'quick_abort_min' to '-1 kb'.
#Default:
# Quick_abort_pct 95

# Tag: read_ahead_gap    buffer-size
# The amount of data the cache will buffer ahead of what has been
# Sent to the client when retrieving an object from another server.
#Default:
# Read_ahead_gap 16 kb

# Tag: negative_ttl    time-units
# Set the default time-to-live (ttl) for failed requests.
# Certain types of failures (such as "connection refused" and
#    "404 Not Found") are able to be negatively-cached for a short time.
# Modern web servers should provide expires: header, however if they
# Do not this can provide a minimum ttl.
# The default is not to cache errors with unknown expiry details.
# Note that this is different from negative caching of dns lookups.
# Warning: doing this violates the http standard.  enabling
# This feature could make you liable for problems which it
# Causes.
#Default:
# Negative_ttl 0 seconds

# Tag: positive_dns_ttl    time-units
# Upper limit on how long squid will cache positive dns responses.
# Default is 6 hours (360 minutes). this directive must be set
# Larger than negative_dns_ttl.
#Default:
# Positive_dns_ttl 6 hours

# Tag: negative_dns_ttl    time-units
# Time-to-live (ttl) for negative caching of failed dns lookups.
# This also sets the lower cache limit on positive lookups.
# Minimum value is 1 second, and it is not recommendable to go
# Much below 10 seconds.
#Default:
# Negative_dns_ttl 1 minutes

# Tag: range_offset_limit    size [acl acl...]
# Usage: (size) [units] [[!]aclname]
# Sets an upper limit on how far (number of bytes) into the file
# A range request    may be to cause squid to prefetch the whole file.
# If beyond this limit, squid forwards the range request as it is and
# The result is not cached.
# This is to stop a far ahead range request (lets say start at 17mb)
# From making squid fetch the whole object up to that point before
# Sending anything to the client.
# Multiple range_offset_limit lines may be specified, and they will
# Be searched from top to bottom on each request until a match is found.
# The first match found will be used.  if no line matches a request, the
# Default limit of 0 bytes will be used.
# 'size' is the limit specified as a number of units.
# 'units' specifies whether to use bytes, kb, mb, etc.
# If no units are specified bytes are assumed.
# A size of 0 causes squid to never fetch more than the
# Client requested. (default)
# A size of 'none' causes squid to always fetch the object from the
# Beginning so it may cache the result. (2.0 style)
# 'aclname' is the name of a defined acl.
# Np: using 'none' as the byte value here will override any quick_abort settings
# That may otherwise apply to the range request. the range request will
# Be fully fetched from start to finish regardless of the client
# Actions. this affects bandwidth usage.
#Default:
# None

# Tag: minimum_expiry_time    (seconds)
# The minimum caching time according to (expires - date)
# Headers squid honors if the object can't be revalidated.
# The default is 60 seconds.
# In reverse proxy environments it might be desirable to honor
# Shorter object lifetimes. it is most likely better to make
# Your server return a meaningful last-modified header however.
# In esi environments where page fragments often have short
# Lifetimes, this will often be best set to 0.
#Default:
# Minimum_expiry_time 60 seconds

# Tag: store_avg_object_size    (bytes)
# Average object size, used to estimate number of objects your
# Cache can hold.  the default is 13 kb.
# This is used to pre-seed the cache index memory allocation to
# Reduce expensive reallocate operations while handling clients
# Traffic. too-large values may result in memory allocation during
# Peak traffic, too-small values will result in wasted memory.
# Check the cache manager 'info' report metrics for the real
# Object sizes seen by your squid before tuning this.
#Default:
# Store_avg_object_size 13 kb

# Tag: store_objects_per_bucket
# Target number of objects per bucket in the store hash table.
# Lowering this value increases the total number of buckets and
# Also the storage maintenance rate.  the default is 20.
#Default:
# Store_objects_per_bucket 20

# Http options
# -----------------------------------------------------------------------------

# Tag: request_header_max_size    (kb)
# This specifies the maximum size for http headers in a request.
# Request headers are usually relatively small (about 512 bytes).
# Placing a limit on the request header size will catch certain
# Bugs (for example with persistent connections) and possibly
# Buffer-overflow or denial-of-service attacks.
#Default:
# Request_header_max_size 64 kb

# Tag: reply_header_max_size    (kb)
# This specifies the maximum size for http headers in a reply.
# Reply headers are usually relatively small (about 512 bytes).
# Placing a limit on the reply header size will catch certain
# Bugs (for example with persistent connections) and possibly
# Buffer-overflow or denial-of-service attacks.
#Default:
# Reply_header_max_size 64 kb

# Tag: request_body_max_size    (bytes)
# This specifies the maximum size for an http request body.
# In other words, the maximum size of a put/post request.
# A user who attempts to send a request with a body larger
# Than this limit receives an "invalid request" error message.
# If you set this parameter to a zero (the default), there will
# Be no limit imposed.
# See also client_request_buffer_max_size for an alternative
# Limitation on client uploads which can be configured.
#Default:
# No limit.

# Tag: client_request_buffer_max_size    (bytes)
# This specifies the maximum buffer size of a client request.
# It prevents squid eating too much memory when somebody uploads
# A large file.
#Default:
# Client_request_buffer_max_size 512 kb

# Tag: broken_posts
# A list of acl elements which, if matched, causes squid to send
# An extra crlf pair after the body of a put/post request.
# Some http servers has broken implementations of put/post,
# And rely on an extra crlf pair sent by some www clients.
# Quote from rfc2616 section 4.1 on this matter:
# Note: certain buggy http/1.0 client implementations generate an
# Extra crlf's after a post request. to restate what is explicitly
# Forbidden by the bnf, an http/1.1 client must not preface or follow
# A request with an extra crlf.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Example:
# Acl buggy_server url_regex ^http://....
# Broken_posts allow buggy_server
#Default:
# Obey rfc 2616.

# Tag: adaptation_uses_indirect_client    on|off
# Controls whether the indirect client ip address (instead of the direct
# Client ip address) is passed to adaptation services.
# See also: follow_x_forwarded_for adaptation_send_client_ip
#Default:
# Adaptation_uses_indirect_client on

# Tag: via    on|off
# If set (default), squid will include a via header in requests and
# Replies as required by rfc2616.
#Default:
# Via on

# Tag: vary_ignore_expire    on|off
# Many http servers supporting vary gives such objects
# Immediate expiry time with no cache-control header
# When requested by a http/1.0 client. this option
# Enables squid to ignore such expiry times until
# Http/1.1 is fully implemented.
# Warning: if turned on this may eventually cause some
# Varying objects not intended for caching to get cached.
#Default:
# Vary_ignore_expire off

# Tag: request_entities
# Squid defaults to deny get and head requests with request entities,
# As the meaning of such requests are undefined in the http standard
# Even if not explicitly forbidden.
# Set this directive to on if you have clients which insists
# On sending request entities in get or head requests. but be warned
# That there is server software (both proxies and web servers) which
# Can fail to properly process this kind of request which may make you
# Vulnerable to cache pollution attacks if enabled.
#Default:
# Request_entities off

# Tag: request_header_access
# Usage: request_header_access header_name allow|deny [!]aclname ...
# Warning: doing this violates the http standard.  enabling
# This feature could make you liable for problems which it
# Causes.
# This option replaces the old 'anonymize_headers' and the
# Older 'http_anonymizer' option with something that is much
# More configurable. a list of acls for each header name allows
# Removal of specific header fields under specific conditions.
# This option only applies to outgoing http request headers (i.e.,
# Headers sent by squid to the next http hop such as a cache peer
# Or an origin server). the option has no effect during cache hit
# Detection. the equivalent adaptation vectoring point in icap
# Terminology is post-cache reqmod.
# The option is applied to individual outgoing request header
# Fields. for each request header field f, squid uses the first
# Qualifying sets of request_header_access rules:
# 1. rules with header_name equal to f's name.
# 2. rules with header_name 'other', provided f's name is not
# On the hard-coded list of commonly used http header names.
# 3. rules with header_name 'all'.
# Within that qualifying rule set, rule acls are checked as usual.
# If acls of an "allow" rule match, the header field is allowed to
# Go through as is. if acls of a "deny" rule match, the header is
# Removed and request_header_replace is then checked to identify
# If the removed header has a replacement. if no rules within the
# Set have matching acls, the header field is left as is.
# For example, to achieve the same behavior as the old
#    'http_anonymizer standard' option, you should use:
# Request_header_access from deny all
# Request_header_access referer deny all
# Request_header_access user-agent deny all
# Or, to reproduce the old 'http_anonymizer paranoid' feature
# You should use:
# Request_header_access authorization allow all
# Request_header_access proxy-authorization allow all
# Request_header_access cache-control allow all
# Request_header_access content-length allow all
# Request_header_access content-type allow all
# Request_header_access date allow all
# Request_header_access host allow all
# Request_header_access if-modified-since allow all
# Request_header_access pragma allow all
# Request_header_access accept allow all
# Request_header_access accept-charset allow all
# Request_header_access accept-encoding allow all
# Request_header_access accept-language allow all
# Request_header_access connection allow all
# Request_header_access all deny all
# Http reply headers are controlled with the reply_header_access directive.
# By default, all headers are allowed (no anonymizing is performed).
#Default:
# No limits.

# Tag: reply_header_access
# Usage: reply_header_access header_name allow|deny [!]aclname ...
# Warning: doing this violates the http standard.  enabling
# This feature could make you liable for problems which it
# Causes.
# This option only applies to reply headers, i.e., from the
# Server to the client.
# This is the same as request_header_access, but in the other
# Direction. please see request_header_access for detailed
# Documentation.
# For example, to achieve the same behavior as the old
#    'http_anonymizer standard' option, you should use:
# Reply_header_access server deny all
# Reply_header_access www-authenticate deny all
# Reply_header_access link deny all
# Or, to reproduce the old 'http_anonymizer paranoid' feature
# You should use:
# Reply_header_access allow allow all
# Reply_header_access www-authenticate allow all
# Reply_header_access proxy-authenticate allow all
# Reply_header_access cache-control allow all
# Reply_header_access content-encoding allow all
# Reply_header_access content-length allow all
# Reply_header_access content-type allow all
# Reply_header_access date allow all
# Reply_header_access expires allow all
# Reply_header_access last-modified allow all
# Reply_header_access location allow all
# Reply_header_access pragma allow all
# Reply_header_access content-language allow all
# Reply_header_access retry-after allow all
# Reply_header_access title allow all
# Reply_header_access content-disposition allow all
# Reply_header_access connection allow all
# Reply_header_access all deny all
# Http request headers are controlled with the request_header_access directive.
# By default, all headers are allowed (no anonymizing is
# Performed).
#Default:
# No limits.

# Tag: request_header_replace
# Usage:   request_header_replace header_name message
# Example: request_header_replace user-agent nutscrape/1.0 (cp/m; 8-bit)
# This option allows you to change the contents of headers
# Denied with request_header_access above, by replacing them
# With some fixed string.
# This only applies to request headers, not reply headers.
# By default, headers are removed if denied.
#Default:
# None

# Tag: reply_header_replace
# Usage:   reply_header_replace header_name message
# Example: reply_header_replace server foo/1.0
# This option allows you to change the contents of headers
# Denied with reply_header_access above, by replacing them
# With some fixed string.
# This only applies to reply headers, not request headers.
# By default, headers are removed if denied.
#Default:
# None

# Tag: request_header_add
# Usage:   request_header_add field-name field-value [ acl ... ]
# Example: request_header_add x-client-ca "ca=%ssl::>cert_issuer" all
# This option adds header fields to outgoing http requests (i.e.,
# Request headers sent by squid to the next http hop such as a
# Cache peer or an origin server). the option has no effect during
# Cache hit detection. the equivalent adaptation vectoring point
# In icap terminology is post-cache reqmod.
# Field-name is a token specifying an http header name. if a
# Standard http header name is used, squid does not check whether
# The new header conflicts with any existing headers or violates
# Http rules. if the request to be modified already contains a
# Field with the same name, the old field is preserved but the
# Header field values are not merged.
# Field-value is either a token or a quoted string. if quoted
# String format is used, then the surrounding quotes are removed
# While escape sequences and %macros are processed.
# One or more squid acls may be specified to restrict header
# Injection to matching requests. as always in squid.conf, all
# Acls in the acl list must be satisfied for the insertion to
# Happen. the request_header_add supports fast acls only.
# See also: reply_header_add.
#Default:
# None

# Tag: reply_header_add
# Usage:   reply_header_add field-name field-value [ acl ... ]
# Example: reply_header_add x-client-ca "ca=%ssl::>cert_issuer" all
# This option adds header fields to outgoing http responses (i.e., response
# Headers delivered by squid to the client). this option has no effect on
# Cache hit detection. the equivalent adaptation vectoring point in
# Icap terminology is post-cache respmod. this option does not apply to
# Successful connect replies.
# Field-name is a token specifying an http header name. if a
# Standard http header name is used, squid does not check whether
# The new header conflicts with any existing headers or violates
# Http rules. if the response to be modified already contains a
# Field with the same name, the old field is preserved but the
# Header field values are not merged.
# Field-value is either a token or a quoted string. if quoted
# String format is used, then the surrounding quotes are removed
# While escape sequences and %macros are processed.
# One or more squid acls may be specified to restrict header
# Injection to matching responses. as always in squid.conf, all
# Acls in the acl list must be satisfied for the insertion to
# Happen. the reply_header_add option supports fast acls only.
# See also: request_header_add.
#Default:
# None

# Tag: note
# This option used to log custom information about the master
# Transaction. for example, an admin may configure squid to log
# Which "user group" the transaction belongs to, where "user group"
# Will be determined based on a set of acls and not [just]
# Authentication information.
# Values of key/value pairs can be logged using %{key}note macros:
# Note key value acl ...
# Logformat myformat ... %{key}note ...
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# None

# Tag: relaxed_header_parser    on|off|warn
# In the default "on" setting squid accepts certain forms
# Of non-compliant http messages where it is unambiguous
# What the sending application intended even if the message
# Is not correctly formatted. the messages is then normalized
# To the correct form when forwarded by squid.
# If set to "warn" then a warning will be emitted in cache.log
# Each time such http error is encountered.
# If set to "off" then such http errors will cause the request
# Or response to be rejected.
#Default:
# Relaxed_header_parser on

# Tag: collapsed_forwarding    (on|off)
# This option controls whether squid is allowed to merge multiple
# Potentially cachable requests for the same uri before squid knows
# Whether the response is going to be cachable.
# When enabled, instead of forwarding each concurrent request for
# The same url, squid just sends the first of them. the other, so
# Called "collapsed" requests, wait for the response to the first
# Request and, if it happens to be cachable, use that response.
# Here, "concurrent requests" means "received after the first
# Request headers were parsed and before the corresponding response
# Headers were parsed".
# This feature is disabled by default: enabling collapsed
# Forwarding needlessly delays forwarding requests that look
# Cachable (when they are collapsed) but then need to be forwarded
# Individually anyway because they end up being for uncachable
# Content. however, in some cases, such as acceleration of highly
# Cachable content with periodic or grouped expiration times, the
# Gains from collapsing [large volumes of simultaneous refresh
# Requests] outweigh losses from such delays.
# Squid collapses two kinds of requests: regular client requests
# Received on one of the listening ports and internal "cache
# Revalidation" requests which are triggered by those regular
# Requests hitting a stale cached object. revalidation collapsing
# Is currently disabled for squid instances containing smp-aware
# Disk or memory caches and for vary-controlled cached objects.
#Default:
# Collapsed_forwarding off

# Tag: collapsed_forwarding_access
# Use this directive to restrict collapsed forwarding to a subset of
# Eligible requests. the directive is checked for regular http
# Requests, internal revalidation requests, and htcp/icp requests.
# Collapsed_forwarding_access allow|deny [!]aclname ...
# This directive cannot force collapsing. it has no effect on
# Collapsing unless collapsed_forwarding is 'on', and all other
# Collapsing preconditions are satisfied.
# * a denied request will not collapse, and future transactions will
# Not collapse on it (even if they are allowed to collapse).
# * an allowed request may collapse, or future transactions may
# Collapse on it (provided they are allowed to collapse).
# This directive is evaluated before receiving http response headers
# And without access to squid-to-peer connection (if any).
# Only fast acls are supported.
# See also: collapsed_forwarding.
#Default:
# Requests may be collapsed if collapsed_forwarding is on.

# Tag: shared_transient_entries_limit    (number of entries)
# This directive limits the size of a table used for sharing current
# Transaction information among smp workers. a table entry stores meta
# Information about a single cache entry being delivered to squid
# Client(s) by one or more smp workers. a single table entry consumes
# Less than 128 shared memory bytes.
# The limit should be significantly larger than the number of
# Concurrent non-collapsed cachable responses leaving squid. for a
# Cache that handles less than 5000 concurrent requests, the default
# Setting of 16384 should be plenty.
# Using excessively large values wastes shared memory. limiting the
# Table size too much results in hash collisions, leading to lower hit
# Ratio and missed smp request collapsing opportunities: transactions
# Left without a table entry cannot cache their responses and are
# Invisible to other concurrent requests for the same resource.
# A zero limit is allowed but unsupported. a positive small limit
# Lowers hit ratio, but zero limit disables a lot of essential
# Synchronization among smp workers, leading to http violations (e.g.,
# Stale hit responses). it also disables shared collapsed forwarding:
# A worker becomes unable to collapse its requests on transactions in
# Other workers, resulting in more trips to the origin server and more
# Cache thrashing.
#Default:
# Shared_transient_entries_limit 16384

# Timeouts
# -----------------------------------------------------------------------------

# Tag: forward_timeout    time-units
# This parameter specifies how long squid should at most attempt in
# Finding a forwarding path for the request before giving up.
#Default:
# Forward_timeout 4 minutes

# Tag: connect_timeout    time-units
# This parameter specifies how long to wait for the tcp connect to
# The requested server or peer to complete before squid should
# Attempt to find another path where to forward the request.
#Default:
# Connect_timeout 1 minute

# Tag: peer_connect_timeout    time-units
# This parameter specifies how long to wait for a pending tcp
# Connection to a peer cache.  the default is 30 seconds.   you
# May also set different timeout values for individual neighbors
# With the 'connect-timeout' option on a 'cache_peer' line.
#Default:
# Peer_connect_timeout 30 seconds

# Tag: read_timeout    time-units
# Applied on peer server connections.
# After each successful read(), the timeout will be extended by this
# Amount.  if no data is read again after this amount of time,
# The request is aborted and logged with err_read_timeout.
# The default is 15 minutes.
#Default:
# Read_timeout 15 minutes

# Tag: write_timeout    time-units
# This timeout is tracked for all connections that have data
# Available for writing and are waiting for the socket to become
# Ready. after each successful write, the timeout is extended by
# The configured amount. if squid has data to write but the
# Connection is not ready for the configured duration, the
# Transaction associated with the connection is terminated. the
# Default is 15 minutes.
#Default:
# Write_timeout 15 minutes

# Tag: request_timeout
# How long to wait for complete http request headers after initial
# Connection establishment.
#Default:
# Request_timeout 5 minutes

# Tag: request_start_timeout
# How long to wait for the first request byte after initial
# Connection establishment.
#Default:
# Request_start_timeout 5 minutes

# Tag: client_idle_pconn_timeout
# How long to wait for the next http request on a persistent
# Client connection after the previous request completes.
#Default:
# Client_idle_pconn_timeout 2 minutes

# Tag: ftp_client_idle_timeout
# How long to wait for an ftp request on a connection to squid ftp_port.
# Many ftp clients do not deal with idle connection closures well,
# Necessitating a longer default timeout than client_idle_pconn_timeout
# Used for incoming http requests.
#Default:
# Ftp_client_idle_timeout 30 minutes

# Tag: client_lifetime    time-units
# The maximum amount of time a client (browser) is allowed to
# Remain connected to the cache process.  this protects the cache
# From having a lot of sockets (and hence file descriptors) tied up
# In a close_wait state from remote clients that go away without
# Properly shutting down (either because of a network failure or
# Because of a poor client implementation).  the default is one
# Day, 1440 minutes.
# Note:  the default value is intended to be much larger than any
# Client would ever need to be connected to your cache.  you
# Should probably change client_lifetime only as a last resort.
# If you seem to have many client connections tying up
# Filedescriptors, we recommend first tuning the read_timeout,
# Request_timeout, persistent_request_timeout and quick_abort values.
#Default:
# Client_lifetime 1 day

# Tag: pconn_lifetime    time-units
# Desired maximum lifetime of a persistent connection.
# When set, squid will close a now-idle persistent connection that
# Exceeded configured lifetime instead of moving the connection into
# The idle connection pool (or equivalent). no effect on ongoing/active
# Transactions. connection lifetime is the time period from the
# Connection acceptance or opening time until "now".
# This limit is useful in environments with long-lived connections
# Where squid configuration or environmental factors change during a
# Single connection lifetime. if unrestricted, some connections may
# Last for hours and even days, ignoring those changes that should
# Have affected their behavior or their existence.
# Currently, a new lifetime value supplied via squid reconfiguration
# Has no effect on already idle connections unless they become busy.
# When set to '0' this limit is not used.
#Default:
# Pconn_lifetime 0 seconds

# Tag: half_closed_clients
# Some clients may shutdown the sending side of their tcp
# Connections, while leaving their receiving sides open.    sometimes,
# Squid can not tell the difference between a half-closed and a
# Fully-closed tcp connection.
# By default, squid will immediately close client connections when
# Read(2) returns "no more data to read."
# Change this option to 'on' and squid will keep open connections
# Until a read(2) or write(2) on the socket returns an error.
# This may show some benefits for reverse proxies. but if not
# It is recommended to leave off.
#Default:
# Half_closed_clients off

# Tag: server_idle_pconn_timeout
# Timeout for idle persistent connections to servers and other
# Proxies.
#Default:
# Server_idle_pconn_timeout 1 minute

# Tag: ident_timeout
# Maximum time to wait for ident lookups to complete.
# If this is too high, and you enabled ident lookups from untrusted
# Users, you might be susceptible to denial-of-service by having
# Many ident requests going at once.
#Default:
# Ident_timeout 10 seconds

# Tag: shutdown_lifetime    time-units
# When sigterm or sighup is received, the cache is put into
#    "shutdown pending" mode until all active sockets are closed.
# This value is the lifetime to set for all open descriptors
# During shutdown mode.  any active clients after this many
# Seconds will receive a 'timeout' message.
#Default:
# Shutdown_lifetime 30

# Administrative parameters
# -----------------------------------------------------------------------------

# Tag: cache_mgr
# Email-address of local cache manager who will receive
# Mail if the cache dies.  the default is "webmaster".
#Default:
# Cache_mgr webmaster

# Tag: mail_from
# From: email-address for mail sent when the cache dies.
# The default is to use 'squid@unique_hostname'.
# See also: unique_hostname directive.
#Default:
# None

# Tag: mail_program
# Email program used to send mail if the cache dies.
# The default is "mail". the specified program must comply
# With the standard unix mail syntax:
# Mail-program recipient < mailfile
# Optional command line options can be specified.
#Default:
# Mail_program mail

# Tag: cache_effective_user
# If you start squid as root, it will change its effective/real
# Uid/gid to the user specified below.  the default is to change
# To uid of proxy.
# See also; cache_effective_group
#Default:
# Cache_effective_user proxy

# Tag: cache_effective_group
# Squid sets the gid to the effective user's default group id
#    (taken from the password file) and supplementary group list
# From the groups membership.
# If you want squid to run with a specific gid regardless of
# The group memberships of the effective user then set this
# To the group (or gid) you want squid to run as. when set
# All other group privileges of the effective user are ignored
# And only this gid is effective. if squid is not started as
# Root the user starting squid must be member of the specified
# Group.
# This option is not recommended by the squid team.
# Our preference is for administrators to configure a secure
# User account for squid with uid/gid matching system policies.
#Default:
# Use system group memberships of the cache_effective_user account

# Tag: httpd_suppress_version_string    on|off
# Suppress squid version string info in http headers and html error pages.
#Default:
# Httpd_suppress_version_string off

# Tag: visible_hostname
# If you want to present a special hostname in error messages, etc,
# Define this.  otherwise, the return value of gethostname()
# Will be used. if you have multiple caches in a cluster and
# Get errors about ip-forwarding you must set them to have individual
# Names with this setting.
#Default:
# Visible_hostname debian-bullseye

# Tag: unique_hostname
# If you want to have multiple machines with the same
#    'visible_hostname' you must give each machine a different
#    'unique_hostname' so forwarding loops can be detected.
#Default:
# Copy the value from visible_hostname

# Tag: hostname_aliases
# A list of other dns names your cache has.
#Default:
# None

# Tag: umask
# Minimum umask which should be enforced while the proxy
# Is running, in addition to the umask set at startup.
# For a traditional octal representation of umasks, start
# Your value with 0.
#Default:
umask 022

# Options for the cache registration service
# -----------------------------------------------------------------------------
# This section contains parameters for the (optional) cache
# Announcement service.  this service is provided to help
# Cache administrators locate one another in order to join or
# Create cache hierarchies.
# An 'announcement' message is sent (via udp) to the registration
# Service by squid.  by default, the announcement message is not
# Sent unless you enable it with 'announce_period' below.
# The announcement message includes your hostname, plus the
# Following information from this configuration file:
# Http_port
# Icp_port
# Cache_mgr
# All current information is processed regularly and made
# Available on the web at http://www.ircache.net/cache/tracker/.

# Tag: announce_period
# This is how frequently to send cache announcements.
# To enable announcing your cache, just set an announce period.
# Example:
# Announce_period 1 day
#Default:
# Announcement messages disabled.

# Tag: announce_host
# Set the hostname where announce registration messages will be sent.
# See also announce_port and announce_file
#Default:
# Announce_host tracker.ircache.net

# Tag: announce_file
# The contents of this file will be included in the announce
# Registration messages.
#Default:
# None

# Tag: announce_port
# Set the port where announce registration messages will be sent.
# See also announce_host and announce_file
#Default:
# Announce_port 3131

# Httpd-accelerator options
# -----------------------------------------------------------------------------

# Tag: httpd_accel_surrogate_id
# Surrogates (http://www.esi.org/architecture_spec_1.0.html)
# Need an identification token to allow control targeting. because
# A farm of surrogates may all perform the same tasks, they may share
# An identification token.
# When the surrogate is a reverse-proxy, this id is also
# Used as cdn-id for cdn-loop detection (rfc 8586).
#Default:
# Visible_hostname is used if no specific id is set.

# Tag: http_accel_surrogate_remote    on|off
# Remote surrogates (such as those in a cdn) honour the header
#    "surrogate-Control: no-store-remote".
# Set this to on to have squid behave as a remote surrogate.
#Default:
# Http_accel_surrogate_remote off

# Tag: esi_parser    libxml2|expat
# Selects the xml parsing library to use when interpreting responses with
# Edge side includes.
# To disable esi handling completely, ./configure squid with --disable-esi.
#Default:
# Selects libxml2 if available at ./configure time or libexpat otherwise.

# Delay pool parameters
# -----------------------------------------------------------------------------

# Tag: delay_pools
# This represents the number of delay pools to be used.  for example,
# If you have one class 2 delay pool and one class 3 delays pool, you
# Have a total of 2 delay pools.
# See also delay_parameters, delay_class, delay_access for pool
# Configuration details.
#Default:
# Delay_pools 0

# Tag: delay_class
# This defines the class of each delay pool.  there must be exactly one
# Delay_class line for each delay pool.  for example, to define two
# Delay pools, one of class 2 and one of class 3, the settings above
# And here would be:
# Example:
# Delay_pools 4      # 4 delay pools
# Delay_class 1 2    # pool 1 is a class 2 pool
# Delay_class 2 3    # pool 2 is a class 3 pool
# Delay_class 3 4    # pool 3 is a class 4 pool
# Delay_class 4 5    # pool 4 is a class 5 pool
# The delay pool classes are:
# Class 1        everything is limited by a single aggregate
# Bucket.
# Class 2     everything is limited by a single aggregate
# Bucket as well as an "individual" bucket chosen
# From bits 25 through 32 of the ipv4 address.
# Class 3        everything is limited by a single aggregate
# Bucket as well as a "network" bucket chosen
# From bits 17 through 24 of the ip address and a
#                "individual" bucket chosen from bits 17 through
# 32 of the ipv4 address.
# Class 4        everything in a class 3 delay pool, with an
# Additional limit on a per user basis. this
# Only takes effect if the username is established
# In advance - by forcing authentication in your
# Http_access rules.
# Class 5        requests are grouped according their tag (see
# External_acl's tag= reply).
# Each pool also requires a delay_parameters directive to configure the pool size
# And speed limits used whenever the pool is applied to a request. along with
# A set of delay_access directives to determine when it is used.
# Note: if an ip address is a.b.c.d
#        -> bits 25 through 32 are "d"
#        -> bits 17 through 24 are "c"
#        -> bits 17 through 32 are "c * 256 + d"
# Note-2: due to the use of bitmasks in class 2,3,4 pools they only apply to
# Ipv4 traffic. class 1 and 5 pools may be used with ipv6 traffic.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# See also delay_parameters and delay_access.
#Default:
# None

# Tag: delay_access
# This is used to determine which delay pool a request falls into.
# Delay_access is sorted per pool and the matching starts with pool 1,
# Then pool 2, ..., and finally pool n. the first delay pool where the
# Request is allowed is selected for the request. if it does not allow
# The request to any pool then the request is not delayed (default).
# For example, if you want some_big_clients in delay
# Pool 1 and lotsa_little_clients in delay pool 2:
# Delay_access 1 allow some_big_clients
# Delay_access 1 deny all
# Delay_access 2 allow lotsa_little_clients
# Delay_access 2 deny all
# Delay_access 3 allow authenticated_clients
# See also delay_parameters and delay_class.
#Default:
# Deny using the pool, unless allow rules exist in squid.conf for the pool.

# Tag: delay_parameters
# This defines the parameters for a delay pool.  each delay pool has
# A number of "buckets" associated with it, as explained in the
# Description of delay_class.
# For a class 1 delay pool, the syntax is:
# Delay_class pool 1
# Delay_parameters pool aggregate
# For a class 2 delay pool:
# Delay_class pool 2
# Delay_parameters pool aggregate individual
# For a class 3 delay pool:
# Delay_class pool 3
# Delay_parameters pool aggregate network individual
# For a class 4 delay pool:
# Delay_class pool 4
# Delay_parameters pool aggregate network individual user
# For a class 5 delay pool:
# Delay_class pool 5
# Delay_parameters pool tagrate
# The option variables are:
# Pool        a pool number - ie, a number between 1 and the
# Number specified in delay_pools as used in
# Delay_class lines.
# Aggregate    the speed limit parameters for the aggregate bucket
#                (class 1, 2, 3).
# Individual    the speed limit parameters for the individual
# Buckets (class 2, 3).
# Network        the speed limit parameters for the network buckets
#                (class 3).
# User        the speed limit parameters for the user buckets
#                (class 4).
# Tagrate        the speed limit parameters for the tag buckets
#                (class 5).
# A pair of delay parameters is written restore/maximum, where restore is
# The number of bytes (not bits - modem and network speeds are usually
# Quoted in bits) per second placed into the bucket, and maximum is the
# Maximum number of bytes which can be in the bucket at any time.
# There must be one delay_parameters line for each delay pool.
# For example, if delay pool number 1 is a class 2 delay pool as in the
# Above example, and is being used to strictly limit each host to 64kbit/sec
#    (plus overheads), with no overall limit, the line is:
# Delay_parameters 1 none 8000/8000
# Note that 8 x 8k byte/sec -> 64k bit/sec.
# Note that the word 'none' is used to represent no limit.
# And, if delay pool number 2 is a class 3 delay pool as in the above
# Example, and you want to limit it to a total of 256kbit/sec (strict limit)
# With each 8-bit network permitted 64kbit/sec (strict limit) and each
# Individual host permitted 4800bit/sec with a bucket maximum size of 64kbits
# To permit a decent web page to be downloaded at a decent speed
#    (if the network is not being limited due to overuse) but slow down
# Large downloads more significantly:
# Delay_parameters 2 32000/32000 8000/8000 600/8000
# Note that 8 x  32k byte/sec ->  256k bit/sec.
# 8 x   8k byte/sec ->   64k bit/sec.
# 8 x 600  byte/sec -> 4800  bit/sec.
# Finally, for a class 4 delay pool as in the example - each user will
# Be limited to 128kbits/sec no matter how many workstations they are logged into.:
# Delay_parameters 4 32000/32000 8000/8000 600/64000 16000/16000
# See also delay_class and delay_access.
#Default:
# None

# Tag: delay_initial_bucket_level    (percent, 0-100)
# The initial bucket percentage is used to determine how much is put
# In each bucket when squid starts, is reconfigured, or first notices
# A host accessing it (in class 2 and class 3, individual hosts and
# Networks only have buckets associated with them once they have been
#    "seen" by squid).
#Default:
# Delay_initial_bucket_level 50

# Client delay pool parameters
# -----------------------------------------------------------------------------

# Tag: client_delay_pools
# This option specifies the number of client delay pools used. it must
# Preceed other client_delay_* options.
# Example:
# Client_delay_pools 2
# See also client_delay_parameters and client_delay_access.
#Default:
# Client_delay_pools 0

# Tag: client_delay_initial_bucket_level    (percent, 0-no_limit)
# This option determines the initial bucket size as a percentage of
# Max_bucket_size from client_delay_parameters. buckets are created
# At the time of the "first" connection from the matching ip. idle
# Buckets are periodically deleted up.
# You can specify more than 100 percent but note that such "oversized"
# Buckets are not refilled until their size goes down to max_bucket_size
# From client_delay_parameters.
# Example:
# Client_delay_initial_bucket_level 50
#Default:
# Client_delay_initial_bucket_level 50

# Tag: client_delay_parameters
# This option configures client-side bandwidth limits using the
# Following format:
# Client_delay_parameters pool speed_limit max_bucket_size
# Pool is an integer id used for client_delay_access matching.
# Speed_limit is bytes added to the bucket per second.
# Max_bucket_size is the maximum size of a bucket, enforced after any
# Speed_limit additions.
# Please see the delay_parameters option for more information and
# Examples.
# Example:
# Client_delay_parameters 1 1024 2048
# Client_delay_parameters 2 51200 16384
# See also client_delay_access.
#Default:
# None

# Tag: client_delay_access
# This option determines the client-side delay pool for the
# Request:
# Client_delay_access pool_id allow|deny acl_name
# All client_delay_access options are checked in their pool id
# Order, starting with pool 1. the first checked pool with allowed
# Request is selected for the request. if no acl matches or there
# Are no client_delay_access options, the request bandwidth is not
# Limited.
# The acl-selected pool is then used to find the
# Client_delay_parameters for the request. client-side pools are
# Not used to aggregate clients. clients are always aggregated
# Based on their source ip addresses (one bucket per source ip).
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# Additionally, only the client tcp connection details are available.
# Acls testing http properties will not work.
# Please see delay_access for more examples.
# Example:
# Client_delay_access 1 allow low_rate_network
# Client_delay_access 2 allow vips_network
# See also client_delay_parameters and client_delay_pools.
#Default:
# Deny use of the pool, unless allow rules exist in squid.conf for the pool.

# Tag: response_delay_pool
# This option configures client response bandwidth limits using the
# Following format:
# Response_delay_pool name [option=value] ...
# Name    the response delay pool name
# Available options:
# Individual-restore    the speed limit of an individual
# Bucket(bytes/s). to be used in conjunction
# With 'individual-maximum'.
# Individual-maximum    the maximum number of bytes which can
# Be placed into the individual bucket. to be used
# In conjunction with 'individual-restore'.
# Aggregate-restore    the speed limit for the aggregate
# Bucket(bytes/s). to be used in conjunction with
#                    'aggregate-maximum'.
# Aggregate-maximum    the maximum number of bytes which can
# Be placed into the aggregate bucket. to be used
# In conjunction with 'aggregate-restore'.
# Initial-bucket-level    the initial bucket size as a percentage
# Of individual-maximum.
# Individual and(or) aggregate bucket options may not be specified,
# Meaning no individual and(or) aggregate speed limitation.
# See also response_delay_pool_access and delay_parameters for
# Terminology details.
#Default:
# None

# Tag: response_delay_pool_access
# Determines whether a specific named response delay pool is used
# For the transaction. the syntax for this directive is:
# Response_delay_pool_access pool_name allow|deny acl_name
# All response_delay_pool_access options are checked in the order
# They appear in this configuration file. the first rule with a
# Matching acl wins. if (and only if) an "allow" rule won, squid
# Assigns the response to the corresponding named delay pool.
#Default:
# Deny use of the pool, unless allow rules exist in squid.conf for the pool.

# Wccpv1 and wccpv2 configuration options
# -----------------------------------------------------------------------------

# Tag: wccp_router
# Use this option to define your wccp ``home'' router for
# Squid.
# Wccp_router supports a single wccp(v1) router
# Wccp2_router supports multiple wccpv2 routers
# Only one of the two may be used at the same time and defines
# Which version of wccp to use.
#Default:
# Wccp disabled.

# Tag: wccp2_router
# Use this option to define your wccp ``home'' router for
# Squid.
# Wccp_router supports a single wccp(v1) router
# Wccp2_router supports multiple wccpv2 routers
# Only one of the two may be used at the same time and defines
# Which version of wccp to use.
#Default:
# Wccpv2 disabled.

# Tag: wccp_version
# This directive is only relevant if you need to set up wccp(v1)
# To some very old and end-of-life cisco routers. in all other
# Setups it must be left unset or at the default setting.
# It defines an internal version in the wccp(v1) protocol,
# With version 4 being the officially documented protocol.
# According to some users, cisco ios 11.2 and earlier only
# Support wccp version 3.  if you're using that or an earlier
# Version of ios, you may need to change this value to 3, otherwise
# Do not specify this parameter.
#Default:
# Wccp_version 4

# Tag: wccp2_rebuild_wait
# If this is enabled squid will wait for the cache dir rebuild to finish
# Before sending the first wccp2 hereiam packet
#Default:
# Wccp2_rebuild_wait on

# Tag: wccp2_forwarding_method
# Wccp2 allows the setting of forwarding methods between the
# Router/switch and the cache.  valid values are as follows:
# Gre - gre encapsulation (forward the packet in a gre/wccp tunnel)
# L2  - l2 redirect (forward the packet using layer 2/mac rewriting)
# Currently (as of ios 12.4) cisco routers only support gre.
# Cisco switches only support the l2 redirect assignment method.
#Default:
# Wccp2_forwarding_method gre

# Tag: wccp2_return_method
# Wccp2 allows the setting of return methods between the
# Router/switch and the cache for packets that the cache
# Decides not to handle.  valid values are as follows:
# Gre - gre encapsulation (forward the packet in a gre/wccp tunnel)
# L2  - l2 redirect (forward the packet using layer 2/mac rewriting)
# Currently (as of ios 12.4) cisco routers only support gre.
# Cisco switches only support the l2 redirect assignment.
# If the "ip wccp redirect exclude in" command has been
# Enabled on the cache interface, then it is still safe for
# The proxy server to use a l2 redirect method even if this
# Option is set to gre.
#Default:
# Wccp2_return_method gre

# Tag: wccp2_assignment_method
# Wccp2 allows the setting of methods to assign the wccp hash
# Valid values are as follows:
# Hash - hash assignment
# Mask - mask assignment
# As a general rule, cisco routers support the hash assignment method
# And cisco switches support the mask assignment method.
#Default:
# Wccp2_assignment_method hash

# Tag: wccp2_service
# Wccp2 allows for multiple traffic services. there are two
# Types: "standard" and "dynamic". the standard type defines
# One service id - http (id 0). the dynamic service ids can be from
# 51 to 255 inclusive.  in order to use a dynamic service id
# One must define the type of traffic to be redirected; this is done
# Using the wccp2_service_info option.
# The "standard" type does not require a wccp2_service_info option,
# Just specifying the service id will suffice.
# Md5 service authentication can be enabled by adding
#    "password=<password>" to the end of this service declaration.
# Examples:
# Wccp2_service standard 0    # for the 'web-cache' standard service
# Wccp2_service dynamic 80    # a dynamic service type which will be
#                    # Fleshed out with subsequent options.
# Wccp2_service standard 0 password=foo
#Default:
# Use the 'web-cache' standard service.

# Tag: wccp2_service_info
# Dynamic wccpv2 services require further information to define the
# Traffic you wish to have diverted.
# The format is:
# Wccp2_service_info <id> protocol=<protocol> flags=<flag>,<flag>..
# Priority=<priority> ports=<port>,<port>..
# The relevant wccpv2 flags:
#    + src_ip_hash, dst_ip_hash
#    + source_port_hash, dst_port_hash
#    + src_ip_alt_hash, dst_ip_alt_hash
#    + src_port_alt_hash, dst_port_alt_hash
#    + ports_source
# The port list can be one to eight entries.
# Example:
# Wccp2_service_info 80 protocol=tcp flags=src_ip_hash,ports_source
# Priority=240 ports=80
# Note: the service id must have been defined by a previous
#    'wccp2_service dynamic <id>' entry.
#Default:
# None

# Tag: wccp2_weight
# Each cache server gets assigned a set of the destination
# Hash proportional to their weight.
#Default:
# Wccp2_weight 10000

# Tag: wccp_address
# Use this option if you require wccp(v1) to use a specific
# Interface address.
# The default behavior is to not bind to any specific address.
#Default:
# Address selected by the operating system.

# Tag: wccp2_address
# Use this option if you require wccpv2 to use a specific
# Interface address.
# The default behavior is to not bind to any specific address.
#Default:
# Address selected by the operating system.

# Persistent connection handling
# -----------------------------------------------------------------------------
# Also see "pconn_timeout" in the timeouts section

# Tag: client_persistent_connections
# Persistent connection support for clients.
# Squid uses persistent connections (when allowed). you can use
# This option to disable persistent connections with clients.
#Default:
# Client_persistent_connections on

# Tag: server_persistent_connections
# Persistent connection support for servers.
# Squid uses persistent connections (when allowed). you can use
# This option to disable persistent connections with servers.
#Default:
# Server_persistent_connections on

# Tag: persistent_connection_after_error
# With this directive the use of persistent connections after
# Http errors can be disabled. useful if you have clients
# Who fail to handle errors on persistent connections proper.
#Default:
# Persistent_connection_after_error on

# Tag: detect_broken_pconn
# Some servers have been found to incorrectly signal the use
# Of http/1.0 persistent connections even on replies not
# Compatible, causing significant delays. this server problem
# Has mostly been seen on redirects.
# By enabling this directive squid attempts to detect such
# Broken replies and automatically assume the reply is finished
# After 10 seconds timeout.
#Default:
# Detect_broken_pconn off

# Cache digest options
# -----------------------------------------------------------------------------

# Tag: digest_generation
# This controls whether the server will generate a cache digest
# Of its contents.  by default, cache digest generation is
# Enabled if squid is compiled with --enable-cache-digests defined.
#Default:
# Digest_generation on

# Tag: digest_bits_per_entry
# This is the number of bits of the server's cache digest which
# Will be associated with the digest entry for a given http
# Method and url (public key) combination.  the default is 5.
#Default:
# Digest_bits_per_entry 5

# Tag: digest_rebuild_period    (seconds)
# This is the wait time between cache digest rebuilds.
#Default:
# Digest_rebuild_period 1 hour

# Tag: digest_rewrite_period    (seconds)
# This is the wait time between cache digest writes to
# Disk.
#Default:
# Digest_rewrite_period 1 hour

# Tag: digest_swapout_chunk_size    (bytes)
# This is the number of bytes of the cache digest to write to
# Disk at a time.  it defaults to 4096 bytes (4kb), the squid
# Default swap page.
#Default:
# Digest_swapout_chunk_size 4096 bytes

# Tag: digest_rebuild_chunk_percentage    (percent, 0-100)
# This is the percentage of the cache digest to be scanned at a
# Time.  by default it is set to 10% of the cache digest.
#Default:
# Digest_rebuild_chunk_percentage 10

# Snmp options
# -----------------------------------------------------------------------------

# Tag: snmp_port
# The port number where squid listens for snmp requests. to enable
# Snmp support set this to a suitable port number. port number
# 3401 is often used for the squid snmp agent. by default it's
# Set to "0" (disabled)
# Example:
# Snmp_port 3401
#Default:
# Snmp disabled.

# Tag: snmp_access
# Allowing or denying access to the snmp port.
# All access to the agent is denied by default.
# Usage:
# Snmp_access allow|deny [!]aclname ...
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Example:
# Snmp_access allow snmppublic localhost
# Snmp_access deny all
#Default:
# Deny, unless rules exist in squid.conf.

# Tag: snmp_incoming_address
# Just like 'udp_incoming_address', but for the snmp port.
# Snmp_incoming_address    is used for the snmp socket receiving
# Messages from snmp agents.
# The default snmp_incoming_address is to listen on all
# Available network interfaces.
#Default:
# Accept snmp packets from all machine interfaces.

# Tag: snmp_outgoing_address
# Just like 'udp_outgoing_address', but for the snmp port.
# Snmp_outgoing_address    is used for snmp packets returned to snmp
# Agents.
# If snmp_outgoing_address is not set it will use the same socket
# As snmp_incoming_address. only change this if you want to have
# Snmp replies sent using another address than where this squid
# Listens for snmp queries.
# Note, snmp_incoming_address and snmp_outgoing_address can not have
# The same value since they both use the same port.
#Default:
# Use snmp_incoming_address or an address selected by the operating system.

# Icp options
# -----------------------------------------------------------------------------

# Tag: icp_port
# The port number where squid sends and receives icp queries to
# And from neighbor caches.  the standard udp port for icp is 3130.
# Example:
# Icp_port 3130
#Default:
# Icp disabled.

# Tag: htcp_port
# The port number where squid sends and receives htcp queries to
# And from neighbor caches.  to turn it on you want to set it to
# 4827.
# Example:
# Htcp_port 4827
#Default:
# Htcp disabled.

# Tag: log_icp_queries    on|off
# If set, icp queries are logged to access.log. you may wish
# Do disable this if your icp load is very high to speed things
# Up or to simplify log analysis.
#Default:
# Log_icp_queries on

# Tag: udp_incoming_address
# Udp_incoming_address    is used for udp packets received from other
# Caches.
# The default behavior is to not bind to any specific address.
# Only change this if you want to have all udp queries received on
# A specific interface/address.
# Note: udp_incoming_address is used by the icp, htcp, and dns
# Modules. altering it will affect all of them in the same manner.
# See also; udp_outgoing_address
# Note, udp_incoming_address and udp_outgoing_address can not
# Have the same value since they both use the same port.
#Default:
# Accept packets from all machine interfaces.

# Tag: udp_outgoing_address
# Udp_outgoing_address    is used for udp packets sent out to other
# Caches.
# The default behavior is to not bind to any specific address.
# Instead it will use the same socket as udp_incoming_address.
# Only change this if you want to have udp queries sent using another
# Address than where this squid listens for udp queries from other
# Caches.
# Note: udp_outgoing_address is used by the icp, htcp, and dns
# Modules. altering it will affect all of them in the same manner.
# See also; udp_incoming_address
# Note, udp_incoming_address and udp_outgoing_address can not
# Have the same value since they both use the same port.
#Default:
# Use udp_incoming_address or an address selected by the operating system.

# Tag: icp_hit_stale    on|off
# If you want to return icp_hit for stale cache objects, set this
# Option to 'on'.  if you have sibling relationships with caches
# In other administrative domains, this should be 'off'.  if you only
# Have sibling relationships with caches under your control,
# It is probably okay to set this to 'on'.
# If set to 'on', your siblings should use the option "allow-miss"
# On their cache_peer lines for connecting to you.
#Default:
# Icp_hit_stale off

# Tag: minimum_direct_hops
# If using the icmp pinging stuff, do direct fetches for sites
# Which are no more than this many hops away.
#Default:
# Minimum_direct_hops 4

# Tag: minimum_direct_rtt    (msec)
# If using the icmp pinging stuff, do direct fetches for sites
# Which are no more than this many rtt milliseconds away.
#Default:
# Minimum_direct_rtt 400

# Tag: netdb_low
# The low water mark for the icmp measurement database.
# Note: high watermark controlled by netdb_high directive.
# These watermarks are counts, not percents.  the defaults are
#    (low) 900 and (high) 1000.  When the high water mark is
# Reached, database entries will be deleted until the low
# Mark is reached.
#Default:
# Netdb_low 900

# Tag: netdb_high
# The high water mark for the icmp measurement database.
# Note: low watermark controlled by netdb_low directive.
# These watermarks are counts, not percents.  the defaults are
#    (low) 900 and (high) 1000.  When the high water mark is
# Reached, database entries will be deleted until the low
# Mark is reached.
#Default:
# Netdb_high 1000

# Tag: netdb_ping_period
# The minimum period for measuring a site.  there will be at
# Least this much delay between successive pings to the same
# Network.  the default is five minutes.
#Default:
# Netdb_ping_period 5 minutes

# Tag: query_icmp    on|off
# If you want to ask your peers to include icmp data in their icp
# Replies, enable this option.
# If your peer has configured squid (during compilation) with
#    '--enable-icmp' that peer will send ICMP pings to origin server
# Sites of the urls it receives.  if you enable this option the
# Icp replies from that peer will include the icmp data (if available).
# Then, when choosing a parent cache, squid will choose the parent with
# The minimal rtt to the origin server.  when this happens, the
# Hierarchy field of the access.log will be
#    "closest_parent_miss".  This option is off by default.
#Default:
# Query_icmp off

# Tag: test_reachability    on|off
# When this is 'on', icp miss replies will be icp_miss_nofetch
# Instead of icp_miss if the target host is not in the icmp
# Database, or has a zero rtt.
#Default:
# Test_reachability off

# Tag: icp_query_timeout    (msec)
# Normally squid will automatically determine an optimal icp
# Query timeout value based on the round-trip-time of recent icp
# Queries.  if you want to override the value determined by
# Squid, set this 'icp_query_timeout' to a non-zero value.  this
# Value is specified in milliseconds, so, to use a 2-second
# Timeout (the old default), you would write:
# Icp_query_timeout 2000
#Default:
# Dynamic detection.

# Tag: maximum_icp_query_timeout    (msec)
# Normally the icp query timeout is determined dynamically.  but
# Sometimes it can lead to very large values (say 5 seconds).
# Use this option to put an upper limit on the dynamic timeout
# Value.  do not use this option to always use a fixed (instead
# Of a dynamic) timeout value. to set a fixed timeout see the
#    'icp_query_timeout' directive.
#Default:
# Maximum_icp_query_timeout 2000

# Tag: minimum_icp_query_timeout    (msec)
# Normally the icp query timeout is determined dynamically.  but
# Sometimes it can lead to very small timeouts, even lower than
# The normal latency variance on your link due to traffic.
# Use this option to put an lower limit on the dynamic timeout
# Value.  do not use this option to always use a fixed (instead
# Of a dynamic) timeout value. to set a fixed timeout see the
#    'icp_query_timeout' directive.
#Default:
# Minimum_icp_query_timeout 5

# Tag: background_ping_rate    time-units
# Controls how often the icp pings are sent to siblings that
# Have background-ping set.
#Default:
# Background_ping_rate 10 seconds

# Multicast icp options
# -----------------------------------------------------------------------------

# Tag: mcast_groups
# This tag specifies a list of multicast groups which your server
# Should join to receive multicasted icp queries.
# Note!  be very careful what you put here!  be sure you
# Understand the difference between an icp _query_ and an icp
# _reply_.  this option is to be set only if you want to receive
# Multicast queries.  do not set this option to send multicast
# Icp (use cache_peer for that).  icp replies are always sent via
# Unicast, so this option does not affect whether or not you will
# Receive replies from multicast group members.
# You must be very careful to not use a multicast address which
# Is already in use by another group of caches.
# If you are unsure about multicast, please read the multicast
# Chapter in the squid faq (http://www.squid-cache.org/faq/).
# Usage: mcast_groups 239.128.16.128 224.0.1.20
# By default, squid doesn't listen on any multicast groups.
#Default:
# None

# Tag: mcast_miss_addr
# Note: this option is only available if squid is rebuilt with the
#       -dmulticast_miss_stream define
# If you enable this option, every "cache miss" url will
# Be sent out on the specified multicast address.
# Do not enable this option unless you are are absolutely
# Certain you understand what you are doing.
#Default:
# Disabled.

# Tag: mcast_miss_ttl
# Note: this option is only available if squid is rebuilt with the
#       -dmulticast_miss_stream define
# This is the time-to-live value for packets multicasted
# When multicasting off cache miss urls is enabled.  by
# Default this is set to 'site scope', i.e. 16.
#Default:
# Mcast_miss_ttl 16

# Tag: mcast_miss_port
# Note: this option is only available if squid is rebuilt with the
#       -dmulticast_miss_stream define
# This is the port number to be used in conjunction with
#    'mcast_miss_addr'.
#Default:
# Mcast_miss_port 3135

# Tag: mcast_miss_encode_key
# Note: this option is only available if squid is rebuilt with the
#       -dmulticast_miss_stream define
# The urls that are sent in the multicast miss stream are
# Encrypted.  this is the encryption key.
#Default:
# Mcast_miss_encode_key xxxxxxxxxxxxxxxx

# Tag: mcast_icp_query_timeout    (msec)
# For multicast peers, squid regularly sends out icp "probes" to
# Count how many other peers are listening on the given multicast
# Address.  this value specifies how long squid should wait to
# Count all the replies.  the default is 2000 msec, or 2
# Seconds.
#Default:
# Mcast_icp_query_timeout 2000

# Internal icon options
# -----------------------------------------------------------------------------

# Tag: icon_directory
# Where the icons are stored. these are normally kept in
#    /usr/share/squid/icons
#Default:
# Icon_directory /usr/share/squid/icons

# Tag: global_internal_static
# This directive controls is squid should intercept all requests for
#    /squid-internal-static/ no matter which host the URL is requesting
#    (default on setting), or if nothing special should be done for
# Such urls (off setting). the purpose of this directive is to make
# Icons etc work better in complex cache hierarchies where it may
# Not always be possible for all corners in the cache mesh to reach
# The server generating a directory listing.
#Default:
# Global_internal_static on

# Tag: short_icon_urls
# If this is enabled squid will use short urls for icons.
# If disabled it will revert to the old behavior of including
# It's own name and port in the url.
# If you run a complex cache hierarchy with a mix of squid and
# Other proxies you may need to disable this directive.
#Default:
# Short_icon_urls on

# Error page options
# -----------------------------------------------------------------------------

# Tag: error_directory
# If you wish to create your own versions of the default
# Error files to customize them to suit your company copy
# The error/template files to another directory and point
# This tag at them.
# Warning: this option will disable multi-language support
# On error pages if used.
# The squid developers are interested in making squid available in
# A wide variety of languages. if you are making translations for a
# Language that squid does not currently provide please consider
# Contributing your translation back to the project.
# Http://wiki.squid-cache.org/translations
# The squid developers working on translations are happy to supply drop-in
# Translated error files in exchange for any new language contributions.
#Default:
# Send error pages in the clients preferred language

# Tag: error_default_language
# Set the default language which squid will send error pages in
# If no existing translation matches the clients language
# Preferences.
# If unset (default) generic english will be used.
# The squid developers are interested in making squid available in
# A wide variety of languages. if you are interested in making
# Translations for any language see the squid wiki for details.
# Http://wiki.squid-cache.org/translations
#Default:
# Generate english language pages.

# Tag: error_log_languages
# Log to cache.log what languages users are attempting to
# Auto-negotiate for translations.
# Successful negotiations are not logged. only failures
# Have meaning to indicate that squid may need an upgrade
# Of its error page translations.
#Default:
# Error_log_languages on

# Tag: err_page_stylesheet
# Css stylesheet to pattern the display of squid default error pages.
# For information on css see http://www.w3.org/style/css/
#Default:
# Err_page_stylesheet /etc/squid/errorpage.css

# Tag: err_html_text
# Html text to include in error messages.  make this a "mailto"
# Url to your admin address, or maybe just a link to your
# Organizations web page.
# To include this in your error messages, you must rewrite
# The error template files (found in the "errors" directory).
# Wherever you want the 'err_html_text' line to appear,
# Insert a %l tag in the error template file.
#Default:
# None

# Tag: email_err_data    on|off
# If enabled, information about the occurred error will be
# Included in the mailto links of the err pages (if %w is set)
# So that the email body contains the data.
# Syntax is <a href="mailto:%w%w">%w</a>
#Default:
# Email_err_data on

# Tag: deny_info
# Usage:   deny_info err_page_name acl
# Or       deny_info http://... acl
# Or       deny_info tcp_reset acl
# This can be used to return a err_ page for requests which
# Do not pass the 'http_access' rules.  squid remembers the last
# Acl it evaluated in http_access, and if a 'deny_info' line exists
# For that acl squid returns a corresponding error page.
# The acl is typically the last acl on the http_access deny line which
# Denied access. the exceptions to this rule are:
#    - when Squid needs to request authentication credentials. It's then
# The first authentication related acl encountered
#    - when none of the http_access lines matches. It's then the last
# Acl processed on the last http_access line.
#    - when the decision to deny access was made by an adaptation service,
# The acl name is the corresponding ecap or icap service_name.
# Np: if providing your own custom error pages with error_directory
# You may also specify them by your custom file name:
# Example: deny_info err_custom_access_denied bad_guys
# By defaut squid will send "403 forbidden". a different 4xx or 5xx
# May be specified by prefixing the file name with the code and a colon.
# E.g. 404:err_custom_access_denied
# Alternatively you can tell squid to reset the tcp connection
# By specifying tcp_reset.
# Or you can specify an error url or url pattern. the browsers will
# Get redirected to the specified url after formatting tags have
# Been replaced. redirect will be done with 302 or 307 according to
# Http/1.1 specs. a different 3xx code may be specified by prefixing
# The url. e.g. 303:http://example.com/
# Url format tags:
#        %a    - username (if available. Password NOT included)
#        %a    - Local listening IP address the client connection was connected to
#        %b    - FTP path URL
#        %e    - Error number
#        %e    - Error description
#        %h    - Squid hostname
#        %h    - Request domain name
#        %i    - Client IP Address
#        %m    - Request Method
#        %o    - Unescaped message result from external ACL helper
#        %o    - Message result from external ACL helper
#        %p    - Request Port number
#        %p    - Request Protocol name
#        %r    - Request URL path
#        %t    - Timestamp in RFC 1123 format
#        %u    - Full canonical URL from client
#              (https URLs terminate with *)
#        %u    - Full canonical URL from client
#        %w    - Admin email from squid.conf
#        %x    - Error name
#        %%    - literal percent (%) code
#Default:
# None

# Options influencing request forwarding
# -----------------------------------------------------------------------------

# Tag: nonhierarchical_direct
# By default, squid will send any non-hierarchical requests
#    (not cacheable request type) direct to origin servers.
# When this is set to "off", squid will prefer to send these
# Requests to parents.
# Note that in most configurations, by turning this off you will only
# Add latency to these request without any improvement in global hit
# Ratio.
# This option only sets a preference. if the parent is unavailable a
# Direct connection to the origin server may still be attempted. to
# Completely prevent direct connections use never_direct.
#Default:
# Nonhierarchical_direct on

# Tag: prefer_direct
# Normally squid tries to use parents for most requests. if you for some
# Reason like it to first try going direct and only use a parent if
# Going direct fails set this to on.
# By combining nonhierarchical_direct off and prefer_direct on you
# Can set up squid to use a parent as a backup path if going direct
# Fails.
# Note: if you want squid to use parents for all requests see
# The never_direct directive. prefer_direct only modifies how squid
# Acts on cacheable requests.
#Default:
# Prefer_direct off

# Tag: cache_miss_revalidate    on|off
# Rfc 7232 defines a conditional request mechanism to prevent
# Response objects being unnecessarily transferred over the network.
# If that mechanism is used by the client and a cache miss occurs
# It can prevent new cache entries being created.
# This option determines whether squid on cache miss will pass the
# Client revalidation request to the server or tries to fetch new
# Content for caching. it can be useful while the cache is mostly
# Empty to more quickly have the cache populated by generating
# Non-conditional gets.
# When set to 'on' (default), squid will pass all client if-* headers
# To the server. this permits server responses without a cacheable
# Payload to be delivered and on miss no new cache entry is created.
# When set to 'off' and if the request is cacheable, squid will
# Remove the clients if-modified-since and if-none-match headers from
# The request sent to the server. this requests a 200 status response
# From the server to create a new cache entry with.
#Default:
# Cache_miss_revalidate on

# Tag: always_direct
# Usage: always_direct allow|deny [!]aclname ...
# Here you can use acl elements to specify requests which should
# Always be forwarded by squid to the origin servers without using
# Any peers.  for example, to always directly forward requests for
# Local servers ignoring any parents or siblings you may have use
# Something like:
# Acl local-servers dstdomain my.domain.net
# Always_direct allow local-servers
# To always forward ftp requests directly, use
# Acl ftp proto ftp
# Always_direct allow ftp
# Note: there is a similar, but opposite option named
#    'never_direct'.  You need to be aware that "always_direct deny
# Foo" is not the same thing as "never_direct allow foo".  you
# May need to use a deny rule to exclude a more-specific case of
# Some other rule.  example:
# Acl local-external dstdomain external.foo.net
# Acl local-servers dstdomain  .foo.net
# Always_direct deny local-external
# Always_direct allow local-servers
# Note: if your goal is to make the client forward the request
# Directly to the origin server bypassing squid then this needs
# To be done in the client configuration. squid configuration
# Can only tell squid how squid should fetch the object.
# Note: this directive is not related to caching. the replies
# Is cached as usual even if you use always_direct. to not cache
# The replies see the 'cache' directive.
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Prevent any cache_peer being used for this request.

# Tag: never_direct
# Usage: never_direct allow|deny [!]aclname ...
# Never_direct is the opposite of always_direct.  please read
# The description for always_direct if you have not already.
# With 'never_direct' you can use acl elements to specify
# Requests which should never be forwarded directly to origin
# Servers.  for example, to force the use of a proxy for all
# Requests, except those in your local domain use something like:
# Acl local-servers dstdomain .foo.net
# Never_direct deny local-servers
# Never_direct allow all
# Or if squid is inside a firewall and there are local intranet
# Servers inside the firewall use something like:
# Acl local-intranet dstdomain .foo.net
# Acl local-external dstdomain external.foo.net
# Always_direct deny local-external
# Always_direct allow local-intranet
# Never_direct allow all
# This clause supports both fast and slow acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
#Default:
# Allow dns results to be used for this request.

# Advanced networking options
# -----------------------------------------------------------------------------

# Tag: incoming_udp_average
# Heavy voodoo here.  i can't even believe you are reading this.
# Are you crazy?  don't even think about adjusting these unless
# You understand the algorithms in comm_select.c first!
#Default:
# Incoming_udp_average 6

# Tag: incoming_tcp_average
# Heavy voodoo here.  i can't even believe you are reading this.
# Are you crazy?  don't even think about adjusting these unless
# You understand the algorithms in comm_select.c first!
#Default:
# Incoming_tcp_average 4

# Tag: incoming_dns_average
# Heavy voodoo here.  i can't even believe you are reading this.
# Are you crazy?  don't even think about adjusting these unless
# You understand the algorithms in comm_select.c first!
#Default:
# Incoming_dns_average 4

# Tag: min_udp_poll_cnt
# Heavy voodoo here.  i can't even believe you are reading this.
# Are you crazy?  don't even think about adjusting these unless
# You understand the algorithms in comm_select.c first!
#Default:
# Min_udp_poll_cnt 8

# Tag: min_dns_poll_cnt
# Heavy voodoo here.  i can't even believe you are reading this.
# Are you crazy?  don't even think about adjusting these unless
# You understand the algorithms in comm_select.c first!
#Default:
# Min_dns_poll_cnt 8

# Tag: min_tcp_poll_cnt
# Heavy voodoo here.  i can't even believe you are reading this.
# Are you crazy?  don't even think about adjusting these unless
# You understand the algorithms in comm_select.c first!
#Default:
# Min_tcp_poll_cnt 8

# Tag: accept_filter
# Freebsd:
# The name of an accept(2) filter to install on squid's
# Listen socket(s).  this feature is perhaps specific to
# Freebsd and requires support in the kernel.
# The 'httpready' filter delays delivering new connections
# To squid until a full http request has been received.
# See the accf_http(9) man page for details.
# The 'dataready' filter delays delivering new connections
# To squid until there is some data to process.
# See the accf_dataready(9) man page for details.
# Linux:
# The 'data' filter delays delivering of new connections
# To squid until there is some data to process by tcp_accept_defer.
# You may optionally specify a number of seconds to wait by
#    'data=N' where N is the number of seconds. Defaults to 30
# If not specified.  see the tcp(7) man page for details.
#EXAMPLE:
## Freebsd
#Accept_filter httpready
## Linux
#Accept_filter data
#Default:
# None

# Tag: client_ip_max_connections
# Set an absolute limit on the number of connections a single
# Client ip can use. any more than this and squid will begin to drop
# New connections from the client until it closes some links.
# Note that this is a global limit. it affects all http, htcp, gopher and ftp
# Connections from the client. for finer control use the acl access controls.
# Requires client_db to be enabled (the default).
# Warning: this may noticably slow down traffic received via external proxies
# Or nat devices and cause them to rebound error messages back to their clients.
#Default:
# No limit.

# Tag: tcp_recv_bufsize    (bytes)
# Size of receive buffer to set for tcp sockets.  probably just
# As easy to change your kernel's default.
# Omit from squid.conf to use the default buffer size.
#Default:
# Use operating system tcp defaults.

# Icap options
# -----------------------------------------------------------------------------

# Tag: icap_enable    on|off
# If you want to enable the icap module support, set this to on.
#Default:
# Icap_enable off

# Tag: icap_connect_timeout
# This parameter specifies how long to wait for the tcp connect to
# The requested icap server to complete before giving up and either
# Terminating the http transaction or bypassing the failure.
# The default for optional services is peer_connect_timeout.
# The default for essential services is connect_timeout.
# If this option is explicitly set, its value applies to all services.
#Default:
# None

# Tag: icap_io_timeout    time-units
# This parameter specifies how long to wait for an i/o activity on
# An established, active icap connection before giving up and
# Either terminating the http transaction or bypassing the
# Failure.
#Default:
# Use read_timeout.

# Tag: icap_service_failure_limit    limit [in memory-depth time-units]
# The limit specifies the number of failures that squid tolerates
# When establishing a new tcp connection with an icap service. if
# The number of failures exceeds the limit, the icap service is
# Not used for new icap requests until it is time to refresh its
# Options.
# A negative value disables the limit. without the limit, an icap
# Service will not be considered down due to connectivity failures
# Between icap options requests.
# Squid forgets icap service failures older than the specified
# Value of memory-depth. the memory fading algorithm
# Is approximate because squid does not remember individual
# Errors but groups them instead, splitting the option
# Value into ten time slots of equal length.
# When memory-depth is 0 and by default this option has no
# Effect on service failure expiration.
# Squid always forgets failures when updating service settings
# Using an icap options transaction, regardless of this option
# Setting.
# For example,
#        # Suspend service usage after 10 failures in 5 seconds:
# Icap_service_failure_limit 10 in 5 seconds
#Default:
# Icap_service_failure_limit 10

# Tag: icap_service_revival_delay
# The delay specifies the number of seconds to wait after an icap
# Options request failure before requesting the options again. the
# Failed icap service is considered "down" until fresh options are
# Fetched.
# The actual delay cannot be smaller than the hardcoded minimum
# Delay of 30 seconds.
#Default:
# Icap_service_revival_delay 180

# Tag: icap_preview_enable    on|off
# The icap preview feature allows the icap server to handle the
# Http message by looking only at the beginning of the message body
# Or even without receiving the body at all. in some environments,
# Previews greatly speedup icap processing.
# During an icap options transaction, the server may tell    squid what
# Http messages should be previewed and how big the preview should be.
# Squid will not use preview if the server did not request one.
# To disable icap preview for all icap services, regardless of
# Individual icap server options responses, set this option to "off".
#Example:
#Icap_preview_enable off
#Default:
# Icap_preview_enable on

# Tag: icap_preview_size
# The default size of preview data to be sent to the icap server.
# This value might be overwritten on a per server basis by options requests.
#Default:
# No preview sent.

# Tag: icap_206_enable    on|off
# 206 (partial content) responses is an icap extension that allows the
# Icap agents to optionally combine adapted and original http message
# Content. the decision to combine is postponed until the end of the
# Icap response. squid supports partial content extension by default.
# Activation of the partial content extension is negotiated with each
# Icap service during options exchange. most icap servers should handle
# Negotation correctly even if they do not support the extension, but
# Some might fail. to disable partial content support for all icap
# Services and to avoid any negotiation, set this option to "off".
# Example:
# Icap_206_enable off
#Default:
# Icap_206_enable on

# Tag: icap_default_options_ttl
# The default ttl value for icap options responses that don't have
# An options-ttl header.
#Default:
# Icap_default_options_ttl 60

# Tag: icap_persistent_connections    on|off
# Whether or not squid should use persistent connections to
# An icap server.
#Default:
# Icap_persistent_connections on

# Tag: adaptation_send_client_ip    on|off
# If enabled, squid shares http client ip information with adaptation
# Services. for icap, squid adds the x-client-ip header to icap requests.
# For ecap, squid sets the libecap::metaclientip transaction option.
# See also: adaptation_uses_indirect_client
#Default:
# Adaptation_send_client_ip off

# Tag: adaptation_send_username    on|off
# This sends authenticated http client username (if available) to
# The adaptation service.
# For icap, the username value is encoded based on the
# Icap_client_username_encode option and is sent using the header
# Specified by the icap_client_username_header option.
#Default:
# Adaptation_send_username off

# Tag: icap_client_username_header
# Icap request header name to use for adaptation_send_username.
#Default:
# Icap_client_username_header x-client-username

# Tag: icap_client_username_encode    on|off
# Whether to base64 encode the authenticated client username.
#Default:
# Icap_client_username_encode off

# Tag: icap_service
# Defines a single icap service using the following format:
# Icap_service id vectoring_point uri [option ...]
# Id: id
# An opaque identifier or name which is used to direct traffic to
# This specific service. must be unique among all adaptation
# Services in squid.conf.
# Vectoring_point: reqmod_precache|reqmod_postcache|respmod_precache|respmod_postcache
# This specifies at which point of transaction processing the
# Icap service should be activated. *_postcache vectoring points
# Are not yet supported.
# Uri: icap://servername:port/servicepath
# Icap server and service location.
# Icaps://servername:port/servicepath
# The "icap:" uri scheme is used for traditional icap server and
# Service location (default port is 1344, connections are not
# Encrypted). the "icaps:" uri scheme is for secure icap
# Services that use ssl/tls-encrypted icap connections (by
# Default, on port 11344).
# Icap does not allow a single service to handle both reqmod and respmod
# Transactions. squid does not enforce that requirement. you can specify
# Services with the same service_url and different vectoring_points. you
# Can even specify multiple identical services as long as their
# Service_names differ.
# To activate a service, use the adaptation_access directive. to group
# Services, use adaptation_service_chain and adaptation_service_set.
# Service options are separated by white space. icap services support
# The following name=value options:
# Bypass=on|off|1|0
# If set to 'on' or '1', the icap service is treated as
# Optional. if the service cannot be reached or malfunctions,
# Squid will try to ignore any errors and process the message as
# If the service was not enabled. no all icap errors can be
# Bypassed.  if set to 0, the icap service is treated as
# Essential and all icap errors will result in an error page
# Returned to the http client.
# Bypass is off by default: services are treated as essential.
# Routing=on|off|1|0
# If set to 'on' or '1', the icap service is allowed to
# Dynamically change the current message adaptation plan by
# Returning a chain of services to be used next. the services
# Are specified using the x-next-services icap response header
# Value, formatted as a comma-separated list of service names.
# Each named service should be configured in squid.conf. other
# Services are ignored. an empty x-next-services value results
# In an empty plan which ends the current adaptation.
# Dynamic adaptation plan may cross or cover multiple supported
# Vectoring points in their natural processing order.
# Routing is not allowed by default: the icap x-next-services
# Response header is ignored.
# Ipv6=on|off
# Only has effect on split-stack systems. the default on those systems
# Is to use ipv4-only connections. when set to 'on' this option will
# Make squid use ipv6-only connections to contact this icap service.
# On-overload=block|bypass|wait|force
# If the service max-connections limit has been reached, do
# One of the following for each new icap transaction:
#          * block:  send an HTTP error response to the client
#          * bypass: ignore the "over-connected" ICAP service
#          * wait:   wait (in a FIFO queue) for an ICAP connection slot
#          * force:  proceed, ignoring the Max-Connections limit
# In smp mode with n workers, each worker assumes the service
# Connection limit is max-connections/n, even though not all
# Workers may use a given service.
# The default value is "bypass" if service is bypassable,
# Otherwise it is set to "wait".
# Max-conn=number
# Use the given number as the max-connections limit, regardless
# Of the max-connections value given by the service, if any.
# Connection-encryption=on|off
# Determines the icap service effect on the connections_encrypted
# Acl.
# The default is "on" for secure icap services (i.e., those
# With the icaps:// service uris scheme) and "off" for plain icap
# Services.
# Does not affect icap connections (e.g., does not turn secure
# Icap on or off).
# ==== icaps / tls options ====
# These options are used for secure icap (icaps://....) services only.
# Tls-cert=/path/to/ssl/certificate
# A client x.509 certificate to use when connecting to
# This icap server.
# Tls-key=/path/to/ssl/key
# The private key corresponding to the previous
# Tls-cert= option.
# If tls-key= is not specified tls-cert= is assumed to
# Reference a pem file containing both the certificate
# And private key.
# Tls-cipher=...    the list of valid tls/ssl ciphers to use when connecting
# To this icap server.
# Tls-min-version=1.n
# The minimum tls protocol version to permit. to control
# Sslv3 use the tls-options= parameter.
# Supported values: 1.0 (default), 1.1, 1.2
# Tls-options=...    specify various openssl library options:
# No_sslv3    disallow the use of sslv3
# Single_dh_use
# Always create a new key when using
# Temporary/ephemeral dh key exchanges
# All       enable various bug workarounds
# Suggested as "harmless" by openssl
# Be warned that this reduces ssl/tls
# Strength to some attacks.
# See the openssl ssl_ctx_set_options documentation for a
# More complete list. options relevant only to sslv2 are
# Not supported.
# Tls-cafile=    pem file containing ca certificates to use when verifying
# The icap server certificate.
# Use to specify intermediate ca certificate(s) if not sent
# By the server. or the full ca chain for the server when
# Using the tls-default-ca=off flag.
# May be repeated to load multiple files.
# Tls-capath=...    a directory containing additional ca certificates to
# Use when verifying the icap server certificate.
# Requires openssl or libressl.
# Tls-crlfile=...    a certificate revocation list file to use when
# Verifying the icap server certificate.
# Tls-flags=...    specify various flags modifying the squid tls implementation:
# Dont_verify_peer
# Accept certificates even if they fail to
# Verify.
# Dont_verify_domain
# Don't verify the icap server certificate
# Matches the server name
# Tls-default-ca[=off]
# Whether to use the system trusted cas. default is on.
# Tls-domain=    the icap server name as advertised in it's certificate.
# Used for verifying the correctness of the received icap
# Server certificate. if not specified the icap server
# Hostname extracted from icap uri will be used.
# Older icap_service format without optional named parameters is
# Deprecated but supported for backward compatibility.
#Example:
#Icap_service svcblocker reqmod_precache icap://icap1.mydomain.net:1344/reqmod bypass=0
#Icap_service svclogger reqmod_precache icaps://icap2.mydomain.net:11344/reqmod routing=on
#Default:
# None

# Tag: icap_class
# This deprecated option was documented to define an icap service
# Chain, even though it actually defined a set of similar, redundant
# Services, and the chains were not supported.
# To define a set of redundant services, please use the
# Adaptation_service_set directive. for service chains, use
# Adaptation_service_chain.
#Default:
# None

# Tag: icap_access
# This option is deprecated. please use adaptation_access, which
# Has the same icap functionality, but comes with better
# Documentation, and ecap support.
#Default:
# None

# Ecap options
# -----------------------------------------------------------------------------

# Tag: ecap_enable    on|off
# Controls whether ecap support is enabled.
#Default:
# Ecap_enable off

# Tag: ecap_service
# Defines a single ecap service
# Ecap_service id vectoring_point uri [option ...]
# Id: id
# An opaque identifier or name which is used to direct traffic to
# This specific service. must be unique among all adaptation
# Services in squid.conf.
# Vectoring_point: reqmod_precache|reqmod_postcache|respmod_precache|respmod_postcache
# This specifies at which point of transaction processing the
# Ecap service should be activated. *_postcache vectoring points
# Are not yet supported.
# Uri: ecap://vendor/service_name?custom&cgi=style&parameters=optional
# Squid uses the ecap service uri to match this configuration
# Line with one of the dynamically loaded services. each loaded
# Ecap service must have a unique uri. obtain the right uri from
# The service provider.
# To activate a service, use the adaptation_access directive. to group
# Services, use adaptation_service_chain and adaptation_service_set.
# Service options are separated by white space. ecap services support
# The following name=value options:
# Bypass=on|off|1|0
# If set to 'on' or '1', the ecap service is treated as optional.
# If the service cannot be reached or malfunctions, squid will try
# To ignore any errors and process the message as if the service
# Was not enabled. no all ecap errors can be bypassed.
# If set to 'off' or '0', the ecap service is treated as essential
# And all ecap errors will result in an error page returned to the
# Http client.
# Bypass is off by default: services are treated as essential.
# Routing=on|off|1|0
# If set to 'on' or '1', the ecap service is allowed to
# Dynamically change the current message adaptation plan by
# Returning a chain of services to be used next.
# Dynamic adaptation plan may cross or cover multiple supported
# Vectoring points in their natural processing order.
# Routing is not allowed by default.
# Connection-encryption=on|off
# Determines the ecap service effect on the connections_encrypted
# Acl.
# Defaults to "on", which does not taint the master transaction
# W.r.t. that acl.
# Does not affect ecap api calls.
# Older ecap_service format without optional named parameters is
# Deprecated but supported for backward compatibility.
#Example:
#Ecap_service s1 reqmod_precache ecap://filters.R.us/leakDetector?on_error=block bypass=off
#Ecap_service s2 respmod_precache ecap://filters.R.us/virusFilter config=/etc/vf.cfg bypass=on
#Default:
# None

# Tag: loadable_modules
# Instructs squid to load the specified dynamic module(s) or activate
# Preloaded module(s).
#Example:
#Loadable_modules /usr/lib/MinimalAdapter.so
#Default:
# None

# Message adaptation options
# -----------------------------------------------------------------------------

# Tag: adaptation_service_set
# Configures an ordered set of similar, redundant services. this is
# Useful when hot standby or backup adaptation servers are available.
# Adaptation_service_set set_name service_name1 service_name2 ...
# The named services are used in the set declaration order. the first
# Applicable adaptation service from the set is used first. the next
# Applicable service is tried if and only if the transaction with the
# Previous service fails and the message waiting to be adapted is still
# Intact.
# When adaptation starts, broken services are ignored as if they were
# Not a part of the set. a broken service is a down optional service.
# The services in a set must be attached to the same vectoring point
#    (e.g., pre-cache) and use the same adaptation method (e.g., REQMOD).
# If all services in a set are optional then adaptation failures are
# Bypassable. if all services in the set are essential, then a
# Transaction failure with one service may still be retried using
# Another service from the set, but when all services fail, the master
# Transaction fails as well.
# A set may contain a mix of optional and essential services, but that
# Is likely to lead to surprising results because broken services become
# Ignored (see above), making previously bypassable failures fatal.
# Technically, it is the bypassability of the last failed service that
# Matters.
# See also: adaptation_access adaptation_service_chain
#Example:
#Adaptation_service_set svcblocker urlFilterPrimary urlFilterBackup
#Adaptation service_set svcLogger loggerLocal loggerRemote
#Default:
# None

# Tag: adaptation_service_chain
# Configures a list of complementary services that will be applied
# One-by-one, forming an adaptation chain or pipeline. this is useful
# When squid must perform different adaptations on the same message.
# Adaptation_service_chain chain_name service_name1 svc_name2 ...
# The named services are used in the chain declaration order. the first
# Applicable adaptation service from the chain is used first. the next
# Applicable service is applied to the successful adaptation results of
# The previous service in the chain.
# When adaptation starts, broken services are ignored as if they were
# Not a part of the chain. a broken service is a down optional service.
# Request satisfaction terminates the adaptation chain because squid
# Does not currently allow declaration of respmod services at the
#    "reqmod_precache" vectoring point (see icap_service or ecap_service).
# The services in a chain must be attached to the same vectoring point
#    (e.g., pre-cache) and use the same adaptation method (e.g., REQMOD).
# A chain may contain a mix of optional and essential services. if an
# Essential adaptation fails (or the failure cannot be bypassed for
# Other reasons), the master transaction fails. otherwise, the failure
# Is bypassed as if the failed adaptation service was not in the chain.
# See also: adaptation_access adaptation_service_set
#Example:
#Adaptation_service_chain svcrequest requestLogger urlFilter leakDetector
#Default:
# None

# Tag: adaptation_access
# Sends an http transaction to an icap or ecap adaptation    service.
# Adaptation_access service_name allow|deny [!]aclname...
# Adaptation_access set_name     allow|deny [!]aclname...
# At each supported vectoring point, the adaptation_access
# Statements are processed in the order they appear in this
# Configuration file. statements pointing to the following services
# Are ignored (i.e., skipped without checking their acl):
# - services serving different vectoring points
#        - "broken-but-bypassable" services
#        - "up" services configured to ignore such transactions
#              (e.g., based on the ICAP Transfer-Ignore header).
# When a set_name is used, all services in the set are checked
# Using the same rules, to find the first applicable one. see
# Adaptation_service_set for details.
# If an access list is checked and there is a match, the
# Processing stops: for an "allow" rule, the corresponding
# Adaptation service is used for the transaction. for a "deny"
# Rule, no adaptation service is activated.
# It is currently not possible to apply more than one adaptation
# Service at the same vectoring point to the same http transaction.
# See also: icap_service and ecap_service
#Example:
#Adaptation_access service_1 allow all
#Default:
# Allow, unless rules exist in squid.conf.

# Tag: adaptation_service_iteration_limit
# Limits the number of iterations allowed when applying adaptation
# Services to a message. if your longest adaptation set or chain
# May have more than 16 services, increase the limit beyond its
# Default value of 16. if detecting infinite iteration loops sooner
# Is critical, make the iteration limit match the actual number
# Of services in your longest adaptation set or chain.
# Infinite adaptation loops are most likely with routing services.
# See also: icap_service routing=1
#Default:
# Adaptation_service_iteration_limit 16

# Tag: adaptation_masterx_shared_names
# For each master transaction (i.e., the http request and response
# Sequence, including all related icap and ecap exchanges), squid
# Maintains a table of metadata. the table entries are (name, value)
# Pairs shared among ecap and icap exchanges. the table is destroyed
# With the master transaction.
# This option specifies the table entry names that squid must accept
# From and forward to the adaptation transactions.
# An icap reqmod or respmod transaction may set an entry in the
# Shared table by returning an icap header field with a name
# Specified in adaptation_masterx_shared_names.
# An ecap reqmod or respmod transaction may set an entry in the
# Shared table by implementing the libecap::visiteachoption() api
# To provide an option with a name specified in
# Adaptation_masterx_shared_names.
# Squid will store and forward the set entry to subsequent adaptation
# Transactions within the same master transaction scope.
# Only one shared entry name is supported at this time.
#Example:
## Share authentication information among ICAP services
#Adaptation_masterx_shared_names x-Subscriber-ID
#Default:
# None

# Tag: adaptation_meta
# This option allows squid administrator to add custom icap request
# Headers or ecap options to squid icap requests or ecap transactions.
# Use it to pass custom authentication tokens and other
# Transaction-state related meta information to an icap/ecap service.
# The addition of a meta header is acl-driven:
# Adaptation_meta name value [!]aclname ...
# Processing for a given header name stops after the first acl list match.
# Thus, it is impossible to add two headers with the same name. if no acl
# Lists match for a given header name, no such header is added. for
# Example:
# # Do not debug transactions except for those that need debugging
# Adaptation_meta x-debug 1 needs_debugging
# # Log all transactions except for those that must remain secret
# Adaptation_meta x-log 1 !keep_secret
# # Mark transactions from users in the "g 1" group
# Adaptation_meta x-authenticated-groups "g 1" authed_as_g1
# The "value" parameter may be a regular squid.conf token or a "double
# Quoted string". within the quoted string, use backslash (\) to escape
# Any character, which is currently only useful for escaping backslashes
# And double quotes. for example,
#        "this string has one backslash (\\) and two \"quotes\""
# Used adaptation_meta header values may be logged via %note
# Logformat code. if multiple adaptation_meta headers with the same name
# Are used during master transaction lifetime, the header values are
# Logged in the order they were used and duplicate values are ignored
#    (only the first repeated value will be logged).
#Default:
# None

# Tag: icap_retry
# This acl determines which retriable icap transactions are
# Retried. transactions that received a complete icap response
# And did not have to consume or produce http bodies to receive
# That response are usually retriable.
# Icap_retry allow|deny [!]aclname ...
# Squid automatically retries some icap i/o timeouts and errors
# Due to persistent connection race conditions.
# See also: icap_retry_limit
#Default:
# Icap_retry deny all

# Tag: icap_retry_limit
# Limits the number of retries allowed.
# Communication errors due to persistent connection race
# Conditions are unavoidable, automatically retried, and do not
# Count against this limit.
# See also: icap_retry
#Default:
# No retries are allowed.

# Dns options
# -----------------------------------------------------------------------------

# Tag: check_hostnames
# For security and stability reasons squid can check
# Hostnames for internet standard rfc compliance. if you want
# Squid to perform these checks turn this directive on.
#Default:
# Check_hostnames off

# Tag: allow_underscore
# Underscore characters is not strictly allowed in internet hostnames
# But nevertheless used by many sites. set this to off if you want
# Squid to be strict about the standard.
# This check is performed only when check_hostnames is set to on.
#Default:
# Allow_underscore on

# Tag: dns_retransmit_interval
# Initial retransmit interval for dns queries. the interval is
# Doubled each time all configured dns servers have been tried.
#Default:
# Dns_retransmit_interval 5 seconds

# Tag: dns_timeout
# Dns query timeout. if no response is received to a dns query
# Within this time all dns servers for the queried domain
# Are assumed to be unavailable.
#Default:
# Dns_timeout 30 seconds

# Tag: dns_packet_max
# Maximum number of bytes packet size to advertise via edns.
# Set to "none" to disable edns large packet support.
# For legacy reasons dns udp replies will default to 512 bytes which
# Is too small for many responses. edns provides a means for squid to
# Negotiate receiving larger responses back immediately without having
# To failover with repeat requests. responses larger than this limit
# Will retain the old behaviour of failover to tcp dns.
# Squid has no real fixed limit internally, but allowing packet sizes
# Over 1500 bytes requires network jumbogram support and is usually not
# Necessary.
# Warning: the rfc also indicates that some older resolvers will reply
# With failure of the whole request if the extension is added. some
# Resolvers have already been identified which will reply with mangled
# Edns response on occasion. usually in response to many-kb jumbogram
# Sizes being advertised by squid.
# Squid will currently treat these both as an unable-to-resolve domain
# Even if it would be resolvable without edns.
#Default:
# Edns disabled

# Tag: dns_defnames    on|off
# Normally the res_defnames resolver option is disabled
#    (see res_init(3)).  This prevents caches in a hierarchy
# From interpreting single-component hostnames locally.  to allow
# Squid to handle single-component names, enable this option.
#Default:
# Search for single-label domain names is disabled.

# Tag: dns_multicast_local    on|off
# When set to on, squid sends multicast dns lookups on the local
# Network for domains ending in .local and .arpa.
# This enables local servers and devices to be contacted in an
# Ad-hoc or zero-configuration network environment.
#Default:
# Search for .local and .arpa names is disabled.

# Tag: dns_nameservers
# Use this if you want to specify a list of dns name servers
#    (ip addresses) to use instead of those given in your
#    /etc/resolv.conf file.
# On windows platforms, if no value is specified here or in
# The /etc/resolv.conf file, the list of dns name servers are
# Taken from the windows registry, both static and dynamic dhcp
# Configurations are supported.
# Example: dns_nameservers 10.0.0.1 192.172.0.4
#Default:
# Use operating system definitions

# Tag: hosts_file
# Location of the host-local ip name-address associations
# Database. most operating systems have such a file on different
# Default locations:
#    - un*X & Linux:    /etc/hosts
#    - windows NT/2000: %SystemRoot%\system32\drivers\etc\hosts
#               (%systemroot% value install default is c:\winnt)
#    - windows XP/2003: %SystemRoot%\system32\drivers\etc\hosts
#               (%systemroot% value install default is c:\windows)
#    - windows 9x/Me:   %windir%\hosts
#               (%windir% value is usually c:\windows)
#    - cygwin:       /etc/hosts
# The file contains newline-separated definitions, in the
# Form ip_address_in_dotted_form name [name ...] names are
# Whitespace-separated. lines beginning with an hash (#)
# Character are comments.
# The file is checked at startup and upon configuration.
# If set to 'none', it won't be checked.
# If append_domain is used, that domain will be added to
# Domain-local (i.e. not containing any dot character) host
# Definitions.
#Default:
# Hosts_file /etc/hosts

# Tag: append_domain
# Appends local domain name to hostnames without any dots in
# Them.  append_domain must begin with a period.
# Be warned there are now internet names with no dots in
# Them using only top-domain names, so setting this may
# Cause some internet sites to become unavailable.
#Example:
# Append_domain .yourdomain.com
#Default:
# Use operating system definitions

# Tag: ignore_unknown_nameservers
# By default squid checks that dns responses are received
# From the same ip addresses they are sent to.  if they
# Don't match, squid ignores the response and writes a warning
# Message to cache.log.  you can allow responses from unknown
# Nameservers by setting this option to 'off'.
#Default:
# Ignore_unknown_nameservers on

# Tag: ipcache_size    (number of entries)
# Maximum number of dns ip cache entries.
#Default:
# Ipcache_size 1024

# Tag: ipcache_low    (percent)
#Default:
# Ipcache_low 90

# Tag: ipcache_high    (percent)
# The size, low-, and high-water marks for the ip cache.
#Default:
# Ipcache_high 95

# Tag: fqdncache_size    (number of entries)
# Maximum number of fqdn cache entries.
#Default:
# Fqdncache_size 1024

# Miscellaneous
# -----------------------------------------------------------------------------

# Tag: configuration_includes_quoted_values    on|off
# If set, squid will recognize each "quoted string" after a configuration
# Directive as a single parameter. the quotes are stripped before the
# Parameter value is interpreted or used.
# See "values with spaces, quotes, and other special characters"
# Section for more details.
#Default:
# Configuration_includes_quoted_values off

# Tag: memory_pools    on|off
# If set, squid will keep pools of allocated (but unused) memory
# Available for future use.  if memory is a premium on your
# System and you believe your malloc library outperforms squid
# Routines, disable this.
#Default:
# Memory_pools on

# Tag: memory_pools_limit    (bytes)
# Used only with memory_pools on:
# Memory_pools_limit 50 mb
# If set to a non-zero value, squid will keep at most the specified
# Limit of allocated (but unused) memory in memory pools. all free()
# Requests that exceed this limit will be handled by your malloc
# Library. squid does not pre-allocate any memory, just safe-keeps
# Objects that otherwise would be free()d. thus, it is safe to set
# Memory_pools_limit to a reasonably high value even if your
# Configuration will use less memory.
# If set to none, squid will keep all memory it can. that is, there
# Will be no limit on the total amount of memory used for safe-keeping.
# To disable memory allocation optimization, do not set
# Memory_pools_limit to 0 or none. set memory_pools to "off" instead.
# An overhead for maintaining memory pools is not taken into account
# When the limit is checked. this overhead is close to four bytes per
# Object kept. however, pools may actually _save_ memory because of
# Reduced memory thrashing in your malloc library.
#Default:
# Memory_pools_limit 5 mb

# Tag: forwarded_for    on|off|transparent|truncate|delete
# If set to "on", squid will append your client's ip address
# In the http requests it forwards. by default it looks like:
# X-forwarded-for: 192.1.2.3
# If set to "off", it will appear as
# X-forwarded-for: unknown
# If set to "transparent", squid will not alter the
# X-forwarded-for header in any way.
# If set to "delete", squid will delete the entire
# X-forwarded-for header.
# If set to "truncate", squid will remove all existing
# X-forwarded-for entries, and place the client ip as the sole entry.
#Default:
# Forwarded_for on

# Tag: cachemgr_passwd
# Specify passwords for cachemgr operations.
# Usage: cachemgr_passwd password action action ...
# Some valid actions are (see cache manager menu for a full list):
# 5min
# 60min
# Asndb
# Authenticator
# Cbdata
# Client_list
# Comm_incoming
# Config *
# Counters
# Delay
# Digest_stats
# Dns
# Events
# Filedescriptors
# Fqdncache
# Histograms
# Http_headers
# Info
# Io
# Ipcache
# Mem
# Menu
# Netdb
# Non_peers
# Objects
# Offline_toggle *
# Pconn
# Peer_select
# Reconfigure *
# Redirector
# Refresh
# Server_list
# Shutdown *
# Store_digest
# Storedir
# Utilization
# Via_headers
# Vm_objects
# * indicates actions which will not be performed without a
# Valid password, others can be performed if not listed here.
# To disable an action, set the password to "disable".
# To allow performing an action without a password, set the
# Password to "none".
# Use the keyword "all" to set the same password for all actions.
#Example:
# Cachemgr_passwd secret shutdown
# Cachemgr_passwd lesssssssecret info stats/objects
# Cachemgr_passwd disable all
#Default:
# No password. actions which require password are denied.

# Tag: client_db    on|off
# If you want to disable collecting per-client statistics,
# Turn off client_db here.
#Default:
# Client_db on

# Tag: refresh_all_ims    on|off
# When you enable this option, squid will always check
# The origin server for an update when a client sends an
# If-modified-since request.  many browsers use ims
# Requests when the user requests a reload, and this
# Ensures those clients receive the latest version.
# By default (off), squid may return a not modified response
# Based on the age of the cached version.
#Default:
# Refresh_all_ims off

# Tag: reload_into_ims    on|off
# When you enable this option, client no-cache or ``reload''
# Requests will be changed to if-modified-since requests.
# Doing this violates the http standard.  enabling this
# Feature could make you liable for problems which it
# Causes.
# See also refresh_pattern for a more selective approach.
#Default:
# Reload_into_ims off

# Tag: connect_retries
# Limits the number of reopening attempts when establishing a single
# Tcp connection. all these attempts must still complete before the
# Applicable connection opening timeout expires.
# By default and when connect_retries is set to zero, squid does not
# Retry failed connection opening attempts.
# The (not recommended) maximum is 10 tries. an attempt to configure a
# Higher value results in the value of 10 being used (with a warning).
# Squid may open connections to retry various high-level forwarding
# Failures. for an outside observer, that activity may look like a
# Low-level connection reopening attempt, but those high-level retries
# Are governed by forward_max_tries instead.
# See also: connect_timeout, forward_timeout, icap_connect_timeout,
# Ident_timeout, and forward_max_tries.
#Default:
# Do not retry failed connections.

# Tag: retry_on_error
# If set to on squid will automatically retry requests when
# Receiving an error response with status 403 (forbidden),
# 500 (internal error), 501 or 503 (service not available).
# Status 502 and 504 (gateway errors) are always retried.
# This is mainly useful if you are in a complex cache hierarchy to
# Work around access control errors.
# Note: this retry will attempt to find another working destination.
# Which is different from the server which just failed.
#Default:
# Retry_on_error off

# Tag: as_whois_server
# Whois server to query for as numbers.  note: as numbers are
# Queried only when squid starts up, not for every request.
#Default:
# As_whois_server whois.ra.net

# Tag: offline_mode
# Enable this option and squid will never try to validate cached
# Objects.
#Default:
# Offline_mode off

# Tag: uri_whitespace
# What to do with requests that have whitespace characters in the
# Uri.  options:
# Strip:  the whitespace characters are stripped out of the url.
# This is the behavior recommended by rfc2396 and rfc3986
# For tolerant handling of generic uri.
# Note: this is one difference between generic uri and http urls.
# Deny:   the request is denied.  the user receives an "invalid
# Request" message.
# This is the behaviour recommended by rfc2616 for safe
# Handling of http request url.
# Allow:  the request is allowed and the uri is not changed.  the
# Whitespace characters remain in the uri.  note the
# Whitespace is passed to redirector processes if they
# Are in use.
# Note this may be considered a violation of rfc2616
# Request parsing where whitespace is prohibited in the
# Url field.
# Encode:    the request is allowed and the whitespace characters are
# Encoded according to rfc1738.
# Chop:    the request is allowed and the uri is chopped at the
# First whitespace.
# Note the current squid implementation of encode and chop violates
# Rfc2616 by not using a 301 redirect after altering the url.
#Default:
# Uri_whitespace strip

# Tag: chroot
# Specifies a directory where squid should do a chroot() while
# Initializing.  this also causes squid to fully drop root
# Privileges after initializing.  this means, for example, if you
# Use a http port less than 1024 and try to reconfigure, you may
# Get an error saying that squid can not open the port.
#Default:
# None

# Tag: pipeline_prefetch
# Http clients may send a pipeline of 1+n requests to squid using a
# Single connection, without waiting for squid to respond to the first
# Of those requests. this option limits the number of concurrent
# Requests squid will try to handle in parallel. if set to n, squid
# Will try to receive and process up to 1+n requests on the same
# Connection concurrently.
# Defaults to 0 (off) for bandwidth management and access logging
# Reasons.
# Note: pipelining requires persistent connections to clients.
# Warning: pipelining breaks ntlm and negotiate/kerberos authentication.
#Default:
# Do not pre-parse pipelined requests.

# Tag: high_response_time_warning    (msec)
# If the one-minute median response time exceeds this value,
# Squid prints a warning with debug level 0 to get the
# Administrators attention.  the value is in milliseconds.
#Default:
# Disabled.

# Tag: high_page_fault_warning
# If the one-minute average page fault rate exceeds this
# Value, squid prints a warning with debug level 0 to get
# The administrators attention.  the value is in page faults
# Per second.
#Default:
# Disabled.

# Tag: high_memory_warning
# Note: this option is only available if squid is rebuilt with the
# Gnu malloc with mstats()
# If the memory usage (as determined by gnumalloc, if available and used)
# Exceeds    this amount, squid prints a warning with debug level 0 to get
# The administrators attention.
#Default:
# Disabled.

# Tag: sleep_after_fork    (microseconds)
# When this is set to a non-zero value, the main squid process
# Sleeps the specified number of microseconds after a fork()
# System call. this sleep may help the situation where your
# System reports fork() failures due to lack of (virtual)
# Memory. note, however, if you have a lot of child
# Processes, these sleep delays will add up and your
# Squid will not service requests for some amount of time
# Until all the child processes have been started.
# On windows value less then 1000 (1 milliseconds) are
# Rounded to 1000.
#Default:
# Sleep_after_fork 0

# Tag: windows_ipaddrchangemonitor    on|off
# Note: this option is only available if squid is rebuilt with the
# Ms windows
# On windows squid by default will monitor ip address changes and will
# Reconfigure itself after any detected event. this is very useful for
# Proxies connected to internet with dial-up interfaces.
# In some cases (a proxy server acting as vpn gateway is one) it could be
# Desiderable to disable this behaviour setting this to 'off'.
# Note: after changing this, squid service must be restarted.
#Default:
# Windows_ipaddrchangemonitor on

# Tag: eui_lookup
# Whether to lookup the eui or mac address of a connected client.
#Default:
# Eui_lookup on

# Tag: max_filedescriptors
# Set the maximum number of filedescriptors, either below the
# Operating system default or up to the hard limit.
# Remove from squid.conf to inherit the current ulimit soft
# Limit setting.
# Note: changing this requires a restart of squid. also
# Not all i/o types supports large values (eg on windows).
#Default:
# Use operating system soft limit set by ulimit.

# Tag: force_request_body_continuation
# This option controls how squid handles data upload requests from http
# And ftp agents that require a "please continue" control message response
# To actually send the request body to squid. it is mostly useful in
# Adaptation environments.
# When squid receives an http request with an "expect: 100-continue"
# Header or an ftp upload command (e.g., stor), squid normally sends the
# Request headers or ftp command information to an adaptation service (or
# Peer) and waits for a response. most adaptation services (and some
# Broken peers) may not respond to squid at that stage because they may
# Decide to wait for the http request body or ftp data transfer. however,
# That request body or data transfer may never come because squid has not
# Responded with the http 100 or ftp 150 (please continue) control message
# To the request sender yet!
# An allow match tells squid to respond with the http 100 or ftp 150
#    (please Continue) control message on its own, before forwarding the
# Request to an adaptation service or peer. such a response usually forces
# The request sender to proceed with sending the body. a deny match tells
# Squid to delay that control response until the origin server confirms
# That the request body is needed. delaying is the default behavior.
#Default:
# Deny, unless rules exist in squid.conf.

# Tag: http_upgrade_request_protocols
# Controls client-initiated and server-confirmed switching from http to
# Another protocol (or to several protocols) using http upgrade mechanism
# Defined in rfc 7230 section 6.7. squid itself does not understand the
# Protocols being upgraded to and participates in the upgraded
# Communication only as a dumb tcp proxy. admins should not allow
# Upgrading to protocols that require a more meaningful proxy
# Participation.
# Usage: http_upgrade_request_protocols <protocol> allow|deny [!]acl ...
# The required "protocol" parameter is either an all-caps word other or an
# Explicit protocol name (e.g. "websocket") optionally followed by a slash
# And a version token (e.g. "http/3"). explicit protocol names and
# Versions are case sensitive.
# When an http client sends an upgrade request header, squid iterates over
# The client-offered protocols and, for each protocol p (with an optional
# Version v), evaluates the first non-empty set of
# Http_upgrade_request_protocols rules (if any) from the following list:
# * all rules with an explicit protocol name equal to p.
#        * all rules that use OTHER instead of a protocol name.
# In other words, rules using other are considered for protocol p if and
# Only if there are no rules mentioning p by name.
# If both of the above sets are empty, then squid removes protocol p from
# The upgrade offer.
# If the client sent a versioned protocol offer p/x, then explicit rules
# Referring to the same-name but different-version protocol p/y are
# Declared inapplicable. inapplicable rules are not evaluated (i.e. are
# Ignored). however, inapplicable rules still belong to the first set of
# Rules for p.
# Within the applicable rule subset, individual rules are evaluated in
# Their configuration order. if all acls of an applicable "allow" rule
# Match, then the protocol offered by the client is forwarded to the next
# Hop as is. if all acls of an applicable "deny" rule match, then the
# Offer is dropped. if no applicable rules have matching acls, then the
# Offer is also dropped. the first matching rule also ends rules
# Evaluation for the offered protocol.
# If all client-offered protocols are removed, then squid forwards the
# Client request without the upgrade header. squid never sends an empty
# Upgrade request header.
# An upgrade request header with a value violating http syntax is dropped
# And ignored without an attempt to use extractable individual protocol
# Offers.
# Upon receiving an http 101 (switching protocols) control message, squid
# Checks that the server listed at least one protocol name and sent a
# Connection:upgrade response header. squid does not understand individual
# Protocol naming and versioning concepts enough to implement stricter
# Checks, but an admin can restrict http 101 (switching protocols)
# Responses further using http_reply_access. responses denied by
# Http_reply_access rules and responses flagged by the internal upgrade
# Checks result in http 502 (bad gateway) err_invalid_resp errors and
# Squid-to-server connection closures.
# If squid sends an upgrade request header, and the next hop (e.g., the
# Origin server) responds with an acceptable http 101 (switching
# Protocols), then squid forwards that message to the client and becomes
# A tcp tunnel.
# The presence of an upgrade request header alone does not preclude cache
# Lookups. in other words, an upgrade request might be satisfied from the
# Cache, using regular http caching rules.
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# Each of the following groups of configuration lines represents a
# Separate configuration example:
# # Never upgrade to protocol foo; all others are ok
# Http_upgrade_request_protocols foo deny all
# Http_upgrade_request_protocols other allow all
# # Only allow upgrades to the protocol bar (except for its first version)
# Http_upgrade_request_protocols bar/1 deny all
# Http_upgrade_request_protocols bar allow all
# Http_upgrade_request_protocols other deny all # this rule is optional
# # Only allow upgrades to protocol baz, and only if baz is the only offer
# Acl upgradeheaderhasmultipleoffers ...
# Http_upgrade_request_protocols baz deny upgradeheaderhasmultipleoffers
# Http_upgrade_request_protocols baz allow all
#Default:
# Upgrade header dropped, effectively blocking an upgrade attempt.

# Tag: server_pconn_for_nonretriable
# This option provides fine-grained control over a persistent connection
# Reuse when forwarding http requests that squid cannot retry. it is useful
# In environments where opening new connections is very expensive
#    (e.g., all connections are secured with TLS with complex client and server
# Certificate validation) and race conditions associated with persistent
# Connections are very rare and/or only cause minor problems.
# Http prohibits retrying unsafe and non-idempotent requests (e.g., post).
# Squid limitations also prohibit retrying all requests with bodies (e.g., put).
# By default, when forwarding such "risky" requests, squid opens a new
# Connection to the server or cache_peer, even if there is an idle persistent
# Connection available. when squid is configured to risk sending a non-retriable
# Request on a previously used persistent connection, and the server closes
# The connection before seeing that risky request, the user gets an error response
# From squid. in most cases, that error response will be http 502 (bad gateway)
# With err_zero_size_object or err_write_error (peer connection reset) error detail.
# If an allow rule matches, squid reuses an available idle persistent connection
#    (if any) for the request that Squid cannot retry. If a deny rule matches, then
# Squid opens a new connection for the request that squid cannot retry.
# This option does not affect requests that squid can retry. they will reuse idle
# Persistent connections (if any).
# This clause only supports fast acl types.
# See http://wiki.squid-cache.org/squidfaq/squidacl for details.
# Example:
# Acl speedisworththerisk method post
# Server_pconn_for_nonretriable allow speedisworththerisk
#Default:
# Open new connections for forwarding requests squid cannot retry safely.

# Tag: happy_eyeballs_connect_timeout    (msec)
# This happy eyeballs (rfc 8305) tuning directive specifies the minimum
# Delay between opening a primary to-server connection and opening a
# Spare to-server connection for the same master transaction. this delay
# Is similar to the connection attempt delay in rfc 8305, but it is only
# Applied to the first spare connection attempt. subsequent spare
# Connection attempts to use happy_eyeballs_connect_gap, and primary
# Connection attempts are not artificially delayed at all.
# Terminology: the "primary" and "spare" designations are determined by
# The order of dns answers received by squid: if squid dns aaaa query
# Was answered first, then primary connections are connections to ipv6
# Peer addresses (while spare connections use ipv4 addresses).
# Similarly, if squid dns a query was answered first, then primary
# Connections are connections to ipv4 peer addresses (while spare
# Connections use ipv6 addresses).
# Shorter happy_eyeballs_connect_timeout values reduce master
# Transaction response time, potentially improving user-perceived
# Response times (i.e., making user eyeballs happier). longer delays
# Reduce both concurrent connection level and server bombardment with
# Connection requests, potentially improving overall squid performance
# And reducing the chance of being blocked by servers for opening too
# Many unused connections.
# Rfc 8305 prohibits happy_eyeballs_connect_timeout values smaller than
# 10 (milliseconds) to "avoid congestion collapse in the presence of
# High packet-loss rates".
# The following happy eyeballs directives place additional connection
# Opening restrictions: happy_eyeballs_connect_gap and
# Happy_eyeballs_connect_limit.
#Default:
# Happy_eyeballs_connect_timeout 250

# Tag: happy_eyeballs_connect_gap    (msec)
# This happy eyeballs (rfc 8305) tuning directive specifies the
# Minimum delay between opening spare to-server connections (to any
# Server; i.e. across all concurrent master transactions in a squid
# Instance). each smp worker currently multiplies the configured gap
# By the total number of workers so that the combined spare connection
# Opening rate of a squid instance obeys the configured limit. the
# Workers do not coordinate connection openings yet; a microburst
# Of spare connection openings may violate the configured gap.
# This directive has similar trade-offs as
# Happy_eyeballs_connect_timeout, but its focus is on limiting traffic
# Amplification effects for squid as a whole, while
# Happy_eyeballs_connect_timeout works on an individual master
# Transaction level.
# The following happy eyeballs directives place additional connection
# Opening restrictions: happy_eyeballs_connect_timeout and
# Happy_eyeballs_connect_limit. see the former for related terminology.
#Default:
# No artificial delays between spare attempts

# Tag: happy_eyeballs_connect_limit
# This happy eyeballs (rfc 8305) tuning directive specifies the
# Maximum number of spare to-server connections (to any server; i.e.
# Across all concurrent master transactions in a squid instance).
# Each smp worker gets an equal share of the total limit. however,
# The workers do not share the actual connection counts yet, so one
#    (busier) worker cannot "borrow" spare connection slots from another
#    (less loaded) worker.
# Setting this limit to zero disables concurrent use of primary and
# Spare tcp connections: spare connection attempts are made only after
# All primary attempts fail. however, squid would still use the
# Dns-related optimizations of the happy eyeballs approach.
# This directive has similar trade-offs as happy_eyeballs_connect_gap,
# But its focus is on limiting squid overheads, while
# Happy_eyeballs_connect_gap focuses on the origin server and peer
# Overheads.
# The following happy eyeballs directives place additional connection
# Opening restrictions: happy_eyeballs_connect_timeout and
# Happy_eyeballs_connect_gap. see the former for related terminology.
#Default:
# No artificial limit on the number of concurrent spare attempts
EOF

cat > "$squid_whitelist" <<EOF
192.168.1.40
.github.com
.google.com
.gmail.com
EOF

cat > "$squid_blacklist" <<EOF
.tiktok.com
.whatsapp.com
EOF

# Install apache2-utils if required so the user can create
# Create a password for the user profile that controls the squid proxy
if ! which htpasswd; then
    sudo apt -y install apache2-utils
    clear
fi

# Run htpasswd to create a password file for the user account that owns the squid proxy server
if [ ! -f "$squid_passwords" ]; then
    if ! htpasswd -c "$squid_passwords" squid; then
        printf "\n%s\n\n" 'The squid passwd file failed to create.'
    else
        printf "\n%s\n\n" 'The squid passwd file was created successfully!'
    fi
    sleep 3
    echo
    "$(type -P cat)" "$squid_passwords"
fi

# Firewall settings
printf "\n%s\n%s\n\n" \
    '[1] Add IPTables and UFW firewall rules' \
    '[2] Skip'
read -p 'Enter a number: ' choice
clear

case "${choice}" in
    1)
            printf "%s\n%s\n\n" \
                'Installing IPTABLES Firewall Rules' \
                '===================================='
            iptables -I INPUT 1 -s 192.168.0.0/16 -p tcp -m tcp --dport 80 -j ACCEPT
            iptables -I INPUT 1 -s 127.0.0.0/8 -p tcp -m tcp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -s 127.0.0.0/8 -p udp -m udp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -s 192.168.0.0/16 -p tcp -m tcp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -s 192.168.0.0/16 -p udp -m udp --dport 53 -j ACCEPT
            iptables -I INPUT 1 -p udp --dport 67:68 --sport 67:68 -j ACCEPT
            iptables -I INPUT 1 -p tcp -m tcp --dport 4711 -i lo -j ACCEPT
            iptables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            ip6tables -I INPUT -p udp -m udp --sport 546:547 --dport 546:547 -j ACCEPT
            ip6tables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
            printf "\n%s\n%s\n\n" \
                'Installing UFW Firewall Rules'
                '=============================='
            ufw allow 53/tcp
            ufw allow 53/udp
            ufw allow 67/tcp
            ufw allow 67/udp
            ufw allow 80/tcp
            ufw allow 546:547/udp
            echo
            read -p 'Press enter to continue.'
            clear
            ;;
    2)      clear;;
    '')     clear;;
    *)
            printf "%s\n\n" 'Bad user input.'
            exit 1
            ;;
esac

# Configure squid to use the squid.conf file created/updated by this script
sudo squid -k reconfigure

# Restart squid to ensure all settings have been applied
sudo service squid restart
clear

# Run a test to check if the proxy is filtering requests
if ! which squidclient &>/dev/null; then
    sudo apt -y install squidclient
fi

squidclient https://google.com
