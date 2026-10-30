#!/usr/bin/env python3
"""Generate the dependency-free Xcode project. Requires Python 3, not XcodeGen.

Only project metadata is generated; source, signing identity and entitlements are
ordinary reviewable files. IDs are stable so regeneration produces small diffs.
"""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
objects = {}


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest().upper()[:24]


def obj(identity, isa, **fields):
    key = uid(identity)
    objects[key] = {'isa': isa, **fields}
    return key


def quoted(value):
    if isinstance(value, dict):
        return '{ ' + ' '.join(f'{quoted(str(k))} = {quoted(v)};' for k, v in value.items()) + ' }'
    if isinstance(value, list):
        return '( ' + ', '.join(quoted(v) for v in value) + ', )' if value else '( )'
    if isinstance(value, int):
        return str(value)
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


def source_group(folder):
    children, builds = [], []
    for path in sorted((ROOT / folder).glob('*.swift')):
        ref = obj(f'file:{folder}/{path.name}', 'PBXFileReference', lastKnownFileType='sourcecode.swift',
                  path=path.name, sourceTree='<group>')
        children.append(ref)
        builds.append(obj(f'build:{folder}/{path.name}', 'PBXBuildFile', fileRef=ref))
    for path in sorted((ROOT / folder).glob('*.xcprivacy')):
        ref = obj(f'file:{folder}/{path.name}', 'PBXFileReference', lastKnownFileType='text.xml',
                  path=path.name, sourceTree='<group>')
        children.append(ref)
    return obj(f'group:{folder}', 'PBXGroup', children=children, path=folder, sourceTree='<group>'), builds


def configurations(name, settings):
    configs = []
    for mode in ('Debug', 'Release'):
        values = {**settings, 'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
                  'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym'}
        if mode == 'Debug':
            values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
            values['ENABLE_TESTABILITY'] = 'YES'
        configs.append(obj(f'{name}:{mode}', 'XCBuildConfiguration', buildSettings=values, name=mode))
    return obj(f'configs:{name}', 'XCConfigurationList', buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')


def generate():
    objects.clear()
    app_group, app_sources = source_group('CAPA')
    widget_group, widget_sources = source_group('CAPAWidget')
    app_product = obj('product:app', 'PBXFileReference', explicitFileType='wrapper.application',
                      includeInIndex=0, path='CAPA.app', sourceTree='BUILT_PRODUCTS_DIR')
    widget_product = obj('product:widget', 'PBXFileReference', explicitFileType='wrapper.app-extension',
                         includeInIndex=0, path='CAPAWidget.appex', sourceTree='BUILT_PRODUCTS_DIR')
    products = obj('products', 'PBXGroup', children=[app_product, widget_product], name='Products', sourceTree='<group>')
    main_group = obj('main-group', 'PBXGroup', children=[app_group, widget_group, products], sourceTree='<group>')
    package = obj('core-package', 'XCLocalSwiftPackageReference', relativePath='CapaCore')
    core = obj('core-product', 'XCSwiftPackageProductDependency', package=package, productName='CapaCore')
    core_build = obj('core-build', 'PBXBuildFile', productRef=core)
    common = {'SDKROOT': 'iphoneos', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SWIFT_VERSION': '5.0',
              'TARGETED_DEVICE_FAMILY': '1', 'CODE_SIGN_STYLE': 'Automatic',
              'MARKETING_VERSION': '0.1.0', 'CURRENT_PROJECT_VERSION': '1',
              'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'targeted'}
    app_config = configurations('app', {**common, 'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.capa',
        'PRODUCT_NAME': '$(TARGET_NAME)', 'INFOPLIST_FILE': 'CAPA/Info.plist',
        'CODE_SIGN_ENTITLEMENTS': 'CAPA/CAPA.entitlements',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
        'APNS_ENVIRONMENT': 'development'})
    # Distribution builds use production APNs; set the bridge sandbox flag to false too.
    objects[uid('app:Release')]['buildSettings']['APNS_ENVIRONMENT'] = 'production'
    widget_config = configurations('widget', {**common, 'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.capa.widget',
        'PRODUCT_NAME': '$(TARGET_NAME)', 'INFOPLIST_FILE': 'CAPAWidget/Info.plist',
        'APPLICATION_EXTENSION_API_ONLY': 'YES', 'SKIP_INSTALL': 'YES',
        'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'})
    project_config = configurations('project', {'CLANG_ENABLE_OBJC_ARC': 'YES', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'})
    app_source_phase = obj('sources:app', 'PBXSourcesBuildPhase', buildActionMask=2147483647,
                           files=app_sources, runOnlyForDeploymentPostprocessing=0)
    widget_source_phase = obj('sources:widget', 'PBXSourcesBuildPhase', buildActionMask=2147483647,
                              files=widget_sources, runOnlyForDeploymentPostprocessing=0)
    frameworks = obj('frameworks:app', 'PBXFrameworksBuildPhase', buildActionMask=2147483647,
                     files=[core_build], runOnlyForDeploymentPostprocessing=0)
    widget_frameworks = obj('frameworks:widget', 'PBXFrameworksBuildPhase', buildActionMask=2147483647,
                            files=[], runOnlyForDeploymentPostprocessing=0)
    privacy = obj('privacy:build', 'PBXBuildFile', fileRef=uid('file:CAPA/PrivacyInfo.xcprivacy'))
    resources = obj('resources:app', 'PBXResourcesBuildPhase', buildActionMask=2147483647,
                    files=[privacy], runOnlyForDeploymentPostprocessing=0)
    widget_resources = obj('resources:widget', 'PBXResourcesBuildPhase', buildActionMask=2147483647,
                           files=[], runOnlyForDeploymentPostprocessing=0)
    embedded = obj('embed:widget', 'PBXBuildFile', fileRef=widget_product, settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
    embed_phase = obj('embed-phase', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647,
                      dstPath='', dstSubfolderSpec=13, files=[embedded], name='Embed App Extensions',
                      runOnlyForDeploymentPostprocessing=0)
    widget_target = obj('target:widget', 'PBXNativeTarget', buildConfigurationList=widget_config,
                        buildPhases=[widget_source_phase, widget_frameworks, widget_resources], buildRules=[],
                        dependencies=[], name='CAPAWidget', productName='CAPAWidget',
                        productReference=widget_product, productType='com.apple.product-type.app-extension')
    proxy = obj('widget-proxy', 'PBXContainerItemProxy', containerPortal=uid('project'), proxyType=1,
                remoteGlobalIDString=widget_target, remoteInfo='CAPAWidget')
    dependency = obj('widget-dependency', 'PBXTargetDependency', target=widget_target, targetProxy=proxy)
    app_target = obj('target:app', 'PBXNativeTarget', buildConfigurationList=app_config,
                     buildPhases=[app_source_phase, frameworks, resources, embed_phase], buildRules=[],
                     dependencies=[dependency], name='CAPA', productName='CAPA', productReference=app_product,
                     productType='com.apple.product-type.application', packageProductDependencies=[core])
    project = obj('project', 'PBXProject', attributes={'LastSwiftUpdateCheck': '1600', 'LastUpgradeCheck': '1600',
                  'TargetAttributes': {app_target: {'CreatedOnToolsVersion': '16.0', 'SystemCapabilities': {
                      'com.apple.Push': {'enabled': 1}, 'com.apple.PushToTalk': {'enabled': 1},
                      'com.apple.BackgroundModes': {'enabled': 1}}}}},
                  buildConfigurationList=project_config, compatibilityVersion='Xcode 14.0', developmentRegion='en',
                  hasScannedForEncodings=0, knownRegions=['en', 'Base'], mainGroup=main_group, productRefGroup=products,
                  projectDirPath='', projectRoot='', targets=[app_target, widget_target], packageReferences=[package])
    directory = ROOT / 'CAPA.xcodeproj'
    directory.mkdir(exist_ok=True)
    data = {'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': project}
    (directory / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + quoted(data) + '\n')
    scheme = directory / 'xcshareddata/xcschemes'
    scheme.mkdir(parents=True, exist_ok=True)
    (scheme / 'CAPA.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="CAPA.app" BlueprintName="CAPA" ReferencedContainer="container:CAPA.xcodeproj"/>
  </BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="CAPA.app" BlueprintName="CAPA" ReferencedContainer="container:CAPA.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="CAPA.app" BlueprintName="CAPA" ReferencedContainer="container:CAPA.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
    print(directory)


if __name__ == '__main__':
    generate()
