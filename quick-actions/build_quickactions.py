#!/usr/bin/env python3
"""Build two Finder Quick Action (.workflow) bundles that wrap a shell script.

These land in the Services / Quick Actions submenu. They are the fallback for
iCloud-managed locations (Desktop, Documents), where Finder's own CloudDocs menu
provider suppresses FinderSync extension items.

Written as a builder rather than hand-edited plists so the script bodies stay in
plain .zsh files (readable, syntax-checkable) and plistlib handles all escaping.
"""

import os
import plistlib
import shutil
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, os.pardir, "scripts")   # single source of truth

ACTIONS = [
    {
        "bundle": "Compress (APFS Transparent).workflow",
        "menu": "Compress (APFS Transparent)",
        "script": "compress.zsh",
    },
    {
        "bundle": "Show Actual Size on Disk.workflow",
        "menu": "Show Actual Size on Disk",
        "script": "showsize.zsh",
    },
    # The VS Code items are top-level only, by request: a Services-submenu copy
    # of something already at the top level is just noise. The cost is that they
    # are unavailable on iCloud-managed Desktop/Documents, where only the
    # Services submenu works — add entries back here if that ever matters.
]


# Stamped into every bundle this builder produces so install.sh and
# uninstall.sh can tell our Quick Actions apart from the user's own.
OWNER_KEY = "MacFinderMenuOwned"


def info_plist(menu_name):
    return {
        OWNER_KEY: True,
        "NSServices": [
            {
                "NSMenuItem": {"default": menu_name},
                "NSMessage": "runWorkflowAsService",
                "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
                "NSSendFileTypes": ["public.item"],
            }
        ]
    }


def wflow(script_body):
    action = {
        "action": {
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": {
                "COMMAND_STRING": script_body,
                "CheckedForUserDefaultShell": True,
                # Verified on macOS 26.6: 0 = pass input to stdin, 1 = pass input
                # as arguments. We want "$@" so paths with spaces and newlines
                # survive intact.
                "inputMethod": 1,
                "shell": "/bin/zsh",
                "source": "",
            },
            "AMAccepts": {
                "Container": "List",
                "Optional": True,
                "Types": ["com.apple.cocoa.string"],
            },
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": {
                "COMMAND_STRING": {},
                "CheckedForUserDefaultShell": {},
                "inputMethod": {},
                "shell": {},
                "source": {},
            },
            "AMProvides": {"Container": "List", "Types": ["com.apple.cocoa.string"]},
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": False,
            "CanShowWhenRun": True,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": str(uuid.uuid4()).upper(),
            "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
            "OutputUUID": str(uuid.uuid4()).upper(),
            "UUID": str(uuid.uuid4()).upper(),
            "UnlocalizedApplications": ["Automator"],
            "arguments": {
                "0": {"default value": 0, "name": "inputMethod", "required": "0", "type": "0", "uuid": "0"},
                "1": {"default value": "", "name": "source", "required": "0", "type": "0", "uuid": "1"},
                "2": {"default value": False, "name": "CheckedForUserDefaultShell", "required": "0", "type": "0", "uuid": "2"},
                "3": {"default value": "", "name": "COMMAND_STRING", "required": "0", "type": "0", "uuid": "3"},
                "4": {"default value": "/bin/sh", "name": "shell", "required": "0", "type": "0", "uuid": "4"},
            },
            "isViewVisible": True,
            "location": "449.000000:253.000000",
            "nibPath": "/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib",
        }
    }

    return {
        "AMApplicationBuild": "528",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [action],
        "connectors": {},
        "workflowMetaData": {
            "applicationBundleIDsByPath": {},
            "applicationPaths": [],
            "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "outputTypeIdentifier": "com.apple.Automator.nothing",
            "presentationMode": 11,
            "processesInput": 0,
            "serviceApplicationBundleID": "com.apple.finder",
            "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
            "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": 0,
            "systemImageName": "NSActionTemplate",
            "useAutomaticInputType": 0,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    }


def main(outdir):
    # Clear the whole output directory, not just the bundles about to be
    # written: a renamed menu item would otherwise leave its old bundle behind
    # for install.sh to pick up and install alongside the new one.
    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    os.makedirs(outdir)

    for spec in ACTIONS:
        with open(os.path.join(SCRIPTS, spec["script"]), "r", encoding="utf-8") as fh:
            body = fh.read()

        bundle = os.path.join(outdir, spec["bundle"])
        contents = os.path.join(bundle, "Contents")
        if os.path.isdir(bundle):
            shutil.rmtree(bundle)
        os.makedirs(contents)

        with open(os.path.join(contents, "Info.plist"), "wb") as fh:
            plistlib.dump(info_plist(spec["menu"]), fh)
        with open(os.path.join(contents, "document.wflow"), "wb") as fh:
            plistlib.dump(wflow(body), fh)

        print("built: %s" % bundle)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "build"))
