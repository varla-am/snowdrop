#!/usr/bin/env python3
"""Regenerates Snowdrop.xcodeproj. Run from anywhere: python3 Scripts/generate-xcodeproj.py

Note: YouTubeAskCore uses `package` access, so the app is built with
`-package-name snowdropdir`. That is the lowercased name of this project folder
(the local package identity). If the folder is renamed, change the flag below.
"""
import os, glob, hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Sources", "Snowdrop")

def oid(name):
    return "5D0" + hashlib.md5(name.encode()).hexdigest()[:21].upper()

# Files inside the synchronized group that must NOT be built into the app.
# The .lproj copies are the SwiftPM variant; Localizable.xcstrings covers the same keys.
exceptions = sorted(
    os.path.relpath(f, SRC)
    for f in glob.glob(os.path.join(SRC, "Resources", "*.lproj", "*"))
) + ["Resources/snowdrop.icns", "Extensions/.gitkeep"]
exceptions = [e for e in exceptions if os.path.exists(os.path.join(SRC, e))]

ID = {k: oid(k) for k in [
    "project", "mainGroup", "srcGroup", "productsGroup", "frameworksGroup", "product",
    "target", "sources", "frameworks", "resources", "projCfgList", "tgtCfgList",
    "projDebug", "projRelease", "tgtDebug", "tgtRelease", "exceptions", "pkgRef",
    "pkgDep", "pkgBuild", "infoPlist", "entitlements", "versionEnv",
    "wTarget", "wProduct", "wGroup", "shGroup", "wSources", "wFrameworks", "wResources", "wCfgList",
    "wDebug", "wRelease", "wInfo", "wEnt", "xEnt", "embedPhase", "embedFile", "depProxy", "dep",
]}

exc_lines = "\n".join(f'\t\t\t\t"{e}",' for e in exceptions)

common = """ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				MACOSX_DEPLOYMENT_TARGET = 15.4;
				SDKROOT = macosx;"""

pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{ID['pkgBuild']} /* YouTubeAskCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {ID['pkgDep']} /* YouTubeAskCore */; }};
		{ID['embedFile']} /* SnowdropWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {ID['wProduct']} /* SnowdropWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{ID['depProxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {ID['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {ID['wTarget']};
			remoteInfo = SnowdropWidgets;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		{ID['embedPhase']} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{ID['embedFile']} /* SnowdropWidgets.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{ID['product']} /* Snowdrop.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Snowdrop.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{ID['infoPlist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{ID['entitlements']} /* Snowdrop.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Snowdrop.entitlements; sourceTree = "<group>"; }};
		{ID['versionEnv']} /* version.env */ = {{isa = PBXFileReference; lastKnownFileType = text; path = version.env; sourceTree = "<group>"; }};
		{ID['wProduct']} /* SnowdropWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = SnowdropWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
		{ID['wInfo']} /* WidgetsInfo.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = WidgetsInfo.plist; sourceTree = "<group>"; }};
		{ID['wEnt']} /* SnowdropWidgets.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = SnowdropWidgets.entitlements; sourceTree = "<group>"; }};
		{ID['xEnt']} /* Snowdrop-Xcode.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = "Snowdrop-Xcode.entitlements"; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		{ID['exceptions']} /* Exceptions for "Snowdrop" folder in "Snowdrop" target */ = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
{exc_lines}
			);
			target = {ID['target']} /* Snowdrop */;
		}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{ID['srcGroup']} /* Snowdrop */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{ID['exceptions']} /* Exceptions for "Snowdrop" folder in "Snowdrop" target */,
			);
			path = Sources/Snowdrop;
			sourceTree = "<group>";
		}};
		{ID['wGroup']} /* Widgets */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Widgets;
			sourceTree = "<group>";
		}};
		{ID['shGroup']} /* Shared */ = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Shared;
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{ID['frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ID['pkgBuild']} /* YouTubeAskCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ID['wFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ID['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{ID['srcGroup']} /* Snowdrop */,
				{ID['wGroup']} /* Widgets */,
				{ID['shGroup']} /* Shared */,
				{ID['infoPlist']} /* Info.plist */,
				{ID['entitlements']} /* Snowdrop.entitlements */,
				{ID['xEnt']} /* Snowdrop-Xcode.entitlements */,
				{ID['wInfo']} /* WidgetsInfo.plist */,
				{ID['wEnt']} /* SnowdropWidgets.entitlements */,
				{ID['versionEnv']} /* version.env */,
				{ID['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{ID['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ID['product']} /* Snowdrop.app */,
				{ID['wProduct']} /* SnowdropWidgets.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ID['target']} /* Snowdrop */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ID['tgtCfgList']} /* Build configuration list for PBXNativeTarget "Snowdrop" */;
			buildPhases = (
				{ID['sources']} /* Sources */,
				{ID['frameworks']} /* Frameworks */,
				{ID['resources']} /* Resources */,
				{ID['embedPhase']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{ID['dep']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{ID['srcGroup']} /* Snowdrop */,
				{ID['shGroup']} /* Shared */,
			);
			name = Snowdrop;
			packageProductDependencies = (
				{ID['pkgDep']} /* YouTubeAskCore */,
			);
			productName = Snowdrop;
			productReference = {ID['product']} /* Snowdrop.app */;
			productType = "com.apple.product-type.application";
		}};
		{ID['wTarget']} /* SnowdropWidgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ID['wCfgList']} /* Build configuration list for PBXNativeTarget "SnowdropWidgets" */;
			buildPhases = (
				{ID['wSources']} /* Sources */,
				{ID['wFrameworks']} /* Frameworks */,
				{ID['wResources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{ID['wGroup']} /* Widgets */,
				{ID['shGroup']} /* Shared */,
			);
			name = SnowdropWidgets;
			productName = SnowdropWidgets;
			productReference = {ID['wProduct']} /* SnowdropWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ID['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
			}};
			buildConfigurationList = {ID['projCfgList']} /* Build configuration list for PBXProject "Snowdrop" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {ID['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{ID['pkgRef']} /* XCLocalSwiftPackageReference "." */,
			);
			productRefGroup = {ID['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ID['target']} /* Snowdrop */,
				{ID['wTarget']} /* SnowdropWidgets */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ID['resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ID['wResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ID['sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ID['wSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{ID['dep']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {ID['wTarget']} /* SnowdropWidgets */;
			targetProxy = {ID['depProxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{ID['projDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				{common}
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{ID['projRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				{common}
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
			}};
			name = Release;
		}};
"""

def target_cfg(key, name):
    return f"""		{ID[key]} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = "Snowdrop-Xcode.entitlements";
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Manual;
				DEVELOPMENT_TEAM = G66D3PLMB8;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = YES;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = Info.plist;
				INFOPLIST_KEY_CFBundleDisplayName = Snowdrop;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.music";
				INFOPLIST_KEY_NSHumanReadableCopyright = "© 2026 Varlaam. Based on Kaset by sozercan (MIT).";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.1.1;
				OTHER_SWIFT_FLAGS = "$(inherited) -package-name snowdropdir";
				PRODUCT_BUNDLE_IDENTIFIER = com.varlaam.Snowdrop;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "SNOWDROP_WIDGETS $(inherited)";
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 6.0;
			}};
			name = {name};
		}};
"""

def widget_cfg(key, name):
    return f"""		{ID[key]} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = SnowdropWidgets.entitlements;
				CODE_SIGN_IDENTITY = "Apple Development";
				CODE_SIGN_STYLE = Manual;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = G66D3PLMB8;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = WidgetsInfo.plist;
				INFOPLIST_KEY_CFBundleDisplayName = "Snowdrop Widgets";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@executable_path/../../../../Frameworks",
				);
				MARKETING_VERSION = 1.1.1;
				PRODUCT_BUNDLE_IDENTIFIER = com.varlaam.Snowdrop.Widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_STRICT_CONCURRENCY = complete;
				SWIFT_VERSION = 6.0;
			}};
			name = {name};
		}};
"""

pbx += target_cfg("tgtDebug", "Debug") + target_cfg("tgtRelease", "Release")
pbx += widget_cfg("wDebug", "Debug") + widget_cfg("wRelease", "Release")
pbx += f"""/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ID['tgtCfgList']} /* Build configuration list for PBXNativeTarget "Snowdrop" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ID['tgtDebug']} /* Debug */,
				{ID['tgtRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ID['wCfgList']} /* Build configuration list for PBXNativeTarget "SnowdropWidgets" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ID['wDebug']} /* Debug */,
				{ID['wRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ID['projCfgList']} /* Build configuration list for PBXProject "Snowdrop" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ID['projDebug']} /* Debug */,
				{ID['projRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{ID['pkgRef']} /* XCLocalSwiftPackageReference "." */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = .;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{ID['pkgDep']} /* YouTubeAskCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {ID['pkgRef']} /* XCLocalSwiftPackageReference "." */;
			productName = YouTubeAskCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {ID['project']} /* Project object */;
}}
"""

out = os.path.join(ROOT, "Snowdrop.xcodeproj")
os.makedirs(out, exist_ok=True)
open(os.path.join(out, "project.pbxproj"), "w").write(pbx)

# Shared scheme, so the app target wins over the package's executable scheme of the same name.
scheme_dir = os.path.join(out, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)
ref = f'''BuildableReference = "FALSE"'''
buildable = f'''<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ID['target']}"
               BuildableName = "Snowdrop.app"
               BlueprintName = "Snowdrop"
               ReferencedContainer = "container:Snowdrop.xcodeproj">
            </BuildableReference>'''
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "NO" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {buildable}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {buildable}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {buildable}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
open(os.path.join(scheme_dir, "Snowdrop.xcscheme"), "w").write(scheme)
print("wrote", out, "-", len(exceptions), "exceptions")
