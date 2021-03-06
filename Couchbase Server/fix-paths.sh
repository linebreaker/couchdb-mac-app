#!/bin/sh -e

instdir=${SRCROOT%dependencies/couchdbx-app}
builddir="${instdir}build/"

dest="$BUILT_PRODUCTS_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/couchdbx-core"

clean_lib() {
#    echo "Cleaning $1"
    while read something
    do
        base=${something##*/}

        if [ $base != "LDAP" ] && [ $base != "Cocoa" ] && [ $base != "CoreFoundation" ] && [ $base != "ExceptionHandling" ]; then
#echo "  Fixing $something -> lib/$base"
            test -f "$dest/lib/$base" || cp "$something" "$dest/lib/$base"
            chmod 755 "$dest/lib/$base"
            install_name_tool -change "$something" "lib/$base" "$1"
        fi
    done
}

ls -la "$dest/bin/couchjs"
ln -f -s "../lib/couchdb/bin/couchjs" "$dest/bin/couchjs"
otool -L "$dest/bin/couchjs"

# The wrong mozjs is installed.  We require homebrew's spidermonkey to
# build, and we link against it, but we've built our own.  This is a
# kind of ugly build hack, but it's why we test.
#rm "$dest/lib/libmozjs.dylib"

# Find and cleanup all libs.
# Do this twice so it picks up libs that got pulled in.
for i in 1 2 3
do
    for fn in "$dest/lib/"*.dylib \
	"$dest/lib/couchdb/erlang/lib/"couch-*/priv/lib/couch_icu_driver.so \
    "$dest/lib/erlang/lib/crypto-2.2/priv/lib/"crypto.so \
    "$dest/bin/couchjs"
    do
	otool -L "$fn" | egrep -v "^[/a-z]" | grep -v /usr/lib \
            | sed -e 's/(\(.*\))//g' | clean_lib "$fn"
    done
done

otool -L "$dest/bin/couchjs"
ls -la "$dest/bin/couchjs"

relativize() {
        # change absolute paths to dynamic absolute paths
        echo relativizing $1
        perl -pi -e "s@$HOME/build/@@g" "$dest/$1"
}

for f in bin/erl bin/js-config bin/icu-config bin/couchdb etc/couchdb/default.ini
do
    relativize $f
done

# Clean up unnecessary items

cd "$dest/lib/erlang/lib"
rm -rf \
    appmon-*/ \
    common_test-*/ \
    cosEvent-*/ \
    cosEventDomain-*/ \
    cosFileTransfer-*/ \
    cosNotification-*/ \
    cosProperty-*/ \
    cosTime-*/ \
    cosTransactions-*/ \
    debugger-*/ \
    dialyzer-*/ \
    docbuilder-*/ \
    edoc-*/ \
    erl_docgen-*/ \
    erl_interface-*/ \
    erts-*/ \
    et-*/ \
    eunit-*/ \
    gs-*/ \
    hipe-*/ \
    ic-*/ \
    inviso-*/ \
    jinterface-*/ \
    megaco-*/ \
    mnesia-*/ \
    observer-*/ \
    odbc-*/ \
    orber-*/ \
    otp_mibs-*/ \
    parsetools-*/ \
    percept-*/ \
    pman-*/ \
    reltool-*/ \
    runtime_tools-*/ \
    snmp-*/ \
    ssh-*/ \
    test_server-*/ \
    toolbar-*/ \
    tools-*/ \
    tv-*/ \
    typer-*/ \
    webtool-*/ \
    wx-*/

rm -rf */{examples,src,include} */priv/obj

cd "$dest"
rm -rf lib/erlang/erts-*/include
rm -rf etc/logrotate.d include info man \
    share/autoconf share/doc share/icu share/emacs share/man share/aclocal* share/automake* share/info \
    lib/*.a lib/icu lib/erlang/usr 
