#!/usr/bin/env python3
"""One-shot: adds the "Swiftfin macOS" native target to Swiftfin.xcodeproj.

Kept in the repo so the target can be re-created after a rebase onto a newer
upstream main, where the project file will have moved.
"""
import re
import sys

PATH = "Swiftfin.xcodeproj/project.pbxproj"
src = open(PATH).read()
if "Swiftfin macOS" in src:
    sys.exit("macOS target already present")

PACKAGES = [
    "Algorithms", "AsyncAlgorithms", "BlurHashKit", "CollectionHStack",
    "CollectionVGrid", "CoreStore", "Defaults",
    "FactoryKit", "Files", "IdentifiedCollections", "JellyfinAPI",
    "KeychainSwift", "MPVUI", "MediaAccessibilityKit", "Nuke", "NukeExtensions",
    "NukeUI", "OrderedCollections", "PerceptionCore", "Pulse",
    "PulseLogHandler", "PulseUI", "SVGKit", "StatefulMacros",
    "SwiftUIIntrospect", "SwiftfinMacros", "Transmission",
]

# iOS-only sources in Swiftfin/ that the macOS target replaces or drops
SWIFTFIN_EXCLUDED = [
    "App/SwiftfinApp.swift",
    "Resources/Info.plist",
    "Resources/Swiftfin.entitlements",
    "App/SwiftfinSpotlight.swift",
    "Extensions/View/Modifiers/PhotoPickerModifier.swift",
    "Views/PhotoCropView/PhotoCropAspectRatios.swift",
    "Views/PhotoCropView/PhotoCropView.swift",
    "Objects/Chromecast/ChromecastController.swift",
    "Components/GestureView.swift",
    "Components/UnmaskSecureField.swift",
    "Components/NotchReader.swift",
]

def ident(n):
    return "F1A0000000000000000000%02X" % n

section = re.search(
    r"/\* Begin XCSwiftPackageProductDependency section \*/(.*?)/\* End", src, re.S
).group(1)
product = {}
for m in re.finditer(r"^\t\t([0-9A-F]{24}) /\* (\S+) \*/ = \{", section, re.M):
    product.setdefault(m.group(2), m.group(1))

GROUP, PRODUCT, TARGET, SOURCES, FRAMEWORKS, RESOURCES = map(ident, range(1, 7))
DEBUG, RELEASE, CONFIGS, EX_MAC, EX_CONFIG, EX_IOS, GITBRANCH = map(ident, range(7, 14))
build_file = {p: ident(0x20 + i) for i, p in enumerate(PACKAGES)}

def insert_before(marker, text):
    global src
    assert marker in src, marker
    src = src.replace(marker, text + marker, 1)

def sub(pattern, repl):
    global src
    src, n = re.subn(pattern, repl, src, count=1, flags=re.S)
    assert n == 1, pattern

insert_before("/* End PBXBuildFile section */", "".join(
    f"\t\t{build_file[p]} /* {p} in Frameworks */ = {{isa = PBXBuildFile; productRef = {product[p]} /* {p} */; }};\n"
    for p in PACKAGES))

insert_before("/* End PBXFileReference section */",
    f'\t\t{PRODUCT} /* Swiftfin macOS.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Swiftfin.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n')

def exception_set(i, paths):
    lines = "".join(f'\t\t\t\t{p if re.fullmatch(r"[A-Za-z0-9_./]+", p) else chr(34) + p + chr(34)},\n' for p in paths)
    return (f"\t\t{i} /* PBXFileSystemSynchronizedBuildFileExceptionSet */ = {{\n"
            "\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n"
            f"\t\t\tmembershipExceptions = (\n{lines}\t\t\t);\n"
            f"\t\t\ttarget = {TARGET} /* Swiftfin macOS */;\n\t\t}};\n")

insert_before("/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */",
    exception_set(EX_MAC, ["Resources/Info.plist", "Resources/Swiftfin.entitlements"])
    + exception_set(EX_CONFIG, ["DevelopmentTeam.xcconfig", "Shared.xcconfig"])
    + exception_set(EX_IOS, SWIFTFIN_EXCLUDED))

EXC = "/* PBXFileSystemSynchronizedBuildFileExceptionSet */"
sub(r'(E14560852DFCAE51008FF700 /\* Swiftfin \*/ = \{isa = PBXFileSystemSynchronizedRootGroup; exceptions = \(.*?)\); explicitFileTypes',
    rf"\g<1>{EX_IOS} {EXC}, ); explicitFileTypes")
sub(r'(E150B7D12DFF2E7C00DC7CF4 /\* XcodeConfig \*/ = \{isa = PBXFileSystemSynchronizedRootGroup; exceptions = \(.*?)\); explicitFileTypes',
    rf"\g<1>{EX_CONFIG} {EXC}, ); explicitFileTypes")
insert_before("/* End PBXFileSystemSynchronizedRootGroup section */",
    f'\t\t{GROUP} /* Swiftfin macOS */ = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = ({EX_MAC} {EXC}, ); explicitFileTypes = {{}}; explicitFolders = (); path = "Swiftfin macOS"; sourceTree = "<group>"; }};\n')

insert_before("/* End PBXFrameworksBuildPhase section */",
    f"\t\t{FRAMEWORKS} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
    + "".join(f"\t\t\t\t{build_file[p]} /* {p} in Frameworks */,\n" for p in PACKAGES)
    + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n")

sub(r"(\t\t\t\tE14560852DFCAE51008FF700 /\* Swiftfin \*/,\n)(\t\t\t\tE145669F2DFCAEFD008FF700 /\* Swiftfin tvOS \*/,\n)",
    rf"\g<1>\t\t\t\t{GROUP} /* Swiftfin macOS */,\n\g<2>")
sub(r"(\t\t\t\t5377CBF1263B596A003A4E83 /\* Swiftfin\.app \*/,\n)",
    rf"\g<1>\t\t\t\t{PRODUCT} /* Swiftfin macOS.app */,\n")

insert_before("/* End PBXNativeTarget section */", f"""\t\t{TARGET} /* Swiftfin macOS */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CONFIGS} /* Build configuration list for PBXNativeTarget "Swiftfin macOS" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES} /* Sources */,
\t\t\t\t{FRAMEWORKS} /* Frameworks */,
\t\t\t\t{RESOURCES} /* Resources */,
\t\t\t\t{GITBRANCH} /* Write Git Branch */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{GROUP} /* Swiftfin macOS */,
\t\t\t\tE14560852DFCAE51008FF700 /* Swiftfin */,
\t\t\t\tE14563272DFCAE6E008FF700 /* Shared */,
\t\t\t\tE1456FC82DFCB323008FF700 /* Translations */,
\t\t\t\tE150B7D12DFF2E7C00DC7CF4 /* XcodeConfig */,
\t\t\t);
\t\t\tname = "Swiftfin macOS";
\t\t\tpackageProductDependencies = (
""" + "".join(f"\t\t\t\t{product[p]} /* {p} */,\n" for p in PACKAGES) + f"""\t\t\t);
\t\t\tproductName = "Swiftfin macOS";
\t\t\tproductReference = {PRODUCT} /* Swiftfin macOS.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
""")

sub(r"(\t\t\t\tTargetAttributes = \{\n)",
    rf"\g<1>\t\t\t\t\t{TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n")
sub(r"(\t\t\ttargets = \(\n\t\t\t\t5377CBF0263B596A003A4E83 /\* Swiftfin iOS \*/,\n)",
    rf"\g<1>\t\t\t\t{TARGET} /* Swiftfin macOS */,\n")

insert_before("/* End PBXResourcesBuildPhase section */",
    f"\t\t{RESOURCES} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
insert_before("/* End PBXSourcesBuildPhase section */",
    f"\t\t{SOURCES} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
insert_before("/* End PBXShellScriptBuildPhase section */", f"""\t\t{GITBRANCH} /* Write Git Branch */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t\t"$(SRCROOT)/Tools/WriteGitBranch.sh",
\t\t\t);
\t\t\tname = "Write Git Branch";
\t\t\toutputPaths = (
\t\t\t\t"$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GitBranch.txt",
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "/bin/sh \\"${{SRCROOT}}/Tools/WriteGitBranch.sh\\"\\n";
\t\t}};
""")

def config(i, name, extra):
    return f"""\t\t{i} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReferenceAnchor = E150B7D12DFF2E7C00DC7CF4 /* XcodeConfig */;
\t\t\tbaseConfigurationReferenceRelativePath = Shared.xcconfig;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = "";
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Swiftfin macOS/Resources/Swiftfin.entitlements";
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "";
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_HARDENED_RUNTIME = NO;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = NO;
\t\t\t\tINFOPLIST_FILE = "Swiftfin macOS/Resources/Info.plist";
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Swiftfin;
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.entertainment";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "org.jellyfin.swiftfin.macos-fork";
\t\t\t\tPRODUCT_NAME = Swiftfin;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSUPPORTED_PLATFORMS = macosx;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
{extra}\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""

insert_before("/* End XCBuildConfiguration section */",
    config(DEBUG, "Debug", "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n")
    + config(RELEASE, "Release",
             '\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";\n'
             "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"
             '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";\n'
             "\t\t\t\tVALIDATE_PRODUCT = YES;\n"))
insert_before("/* End XCConfigurationList section */", f"""\t\t{CONFIGS} /* Build configuration list for PBXNativeTarget "Swiftfin macOS" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG} /* Debug */,
\t\t\t\t{RELEASE} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
""")

open(PATH, "w").write(src)
print("added Swiftfin macOS target")
