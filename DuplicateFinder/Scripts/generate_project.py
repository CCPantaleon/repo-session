from pathlib import Path
root = Path(__file__).resolve().parents[1]
def write(path,text):
 p=root/path; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text.strip()+'\n')
# Deterministic, dependency-free OpenStep project generation.
import hashlib,json
objects={}
def ID(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
class Ref(str): pass
def ref(key): return Ref(ID(key))
def add(key,isa,**props): objects[ID(key)]={'isa':isa,**props};return ref(key)
def render(value,indent=0):
 if isinstance(value,Ref):return str(value)
 if isinstance(value,dict):return '{\n'+''.join('\t'*(indent+1)+str(k)+' = '+render(v,indent+1)+';\n' for k,v in value.items())+'\t'*indent+'}'
 if isinstance(value,list):return '(\n'+''.join('\t'*(indent+1)+render(x,indent+1)+',\n' for x in value)+'\t'*indent+')'
 return json.dumps(str(value))
sourcegroups={}
for target,folder in [('core','Sources/DuplicateFinderCore'),('app','Sources/DuplicateFinderApp'),('test','Tests/DuplicateFinderCoreTests'),('apptest','Tests/DuplicateFinderAppTests')]:
 refs=[];build=[]
 for path in sorted((root/folder).rglob('*.swift')):
  rel=str(path.relative_to(root));f=add('file:'+rel,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=rel,sourceTree='<group>');refs.append(f)
  build.append(add('build:'+rel,'PBXBuildFile',fileRef=f))
 sourcegroups[target]=add('group:'+target,'PBXGroup',children=refs,name=folder,sourceTree='<group>')
 add('sources:'+target,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=build,runOnlyForDeploymentPostprocessing=0)
config=add('file:base','PBXFileReference',lastKnownFileType='text.xcconfig',path='Configuration/Base.xcconfig',sourceTree='<group>')
ent=add('file:ent','PBXFileReference',lastKnownFileType='text.plist.entitlements',path='Configuration/DuplicateFinder.entitlements',sourceTree='<group>')
appinfo=add('file:appinfo','PBXFileReference',lastKnownFileType='text.plist.xml',path='Configuration/AppInfo.plist',sourceTree='<group>')
icon=add('file:icon','PBXFileReference',lastKnownFileType='image.icns',path='Resources/AppIcon.icns',sourceTree='<group>')
products=[]
for key,name,ext,typ in [('core','DuplicateFinderCore','framework','wrapper.framework'),('app','DuplicateFinder','app','wrapper.application'),('test','DuplicateFinderCoreTests','xctest','wrapper.cfbundle'),('apptest','DuplicateFinderAppTests','xctest','wrapper.cfbundle')]:
 products.append(add('product:'+key,'PBXFileReference',explicitFileType=typ,includeInIndex=0,path=name+'.'+ext,sourceTree='BUILT_PRODUCTS_DIR'))
 for mode in ['Debug','Release']:
  settings={'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'com.example.'+name,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '', 'ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO'}
  if key=='core':settings.update({'LD_DYLIB_INSTALL_NAME':'@rpath/$(EXECUTABLE_PATH)','DEFINES_MODULE':'YES','SKIP_INSTALL':'YES','INSTALL_PATH':'$(LOCAL_LIBRARY_DIR)/Frameworks'})
  if key=='app':settings.update({'PRODUCT_BUNDLE_IDENTIFIER':'com.example.DuplicateFinder.Development','PRODUCT_MODULE_NAME':'DuplicateFinderApp','CODE_SIGN_ENTITLEMENTS':'Configuration/DuplicateFinder.entitlements','INFOPLIST_KEY_CFBundleDisplayName':'Duplicate Finder','INFOPLIST_FILE':'Configuration/AppInfo.plist','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.utilities','INFOPLIST_KEY_NSPrincipalClass':'NSApplication','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/../Frameworks']})
  if key in ['test','apptest']:settings.update({'GENERATE_INFOPLIST_FILE':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@loader_path/../Frameworks','@loader_path/../../..']})
  if key=='apptest':settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/DuplicateFinder.app/Contents/MacOS/DuplicateFinder','BUNDLE_LOADER':'$(TEST_HOST)'})
  add('config:'+key+mode,'XCBuildConfiguration',baseConfigurationReference=config,buildSettings=settings,name=mode)
 add('configs:'+key,'XCConfigurationList',buildConfigurations=[ref('config:'+key+m) for m in ['Debug','Release']],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
 links=[]
 if key!='core':
  links.append(add('link:'+key,'PBXBuildFile',fileRef=ref('product:core')))
  proxy=add('proxy:'+key,'PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('target:core'),remoteInfo='DuplicateFinderCore')
  add('dependency:'+key,'PBXTargetDependency',target=ref('target:core'),targetProxy=proxy)
 if key=='apptest':
  proxy=add('proxy:apptestApp','PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('target:app'),remoteInfo='DuplicateFinder')
  add('dependency:apptestApp','PBXTargetDependency',target=ref('target:app'),targetProxy=proxy)
 add('frameworks:'+key,'PBXFrameworksBuildPhase',buildActionMask=2147483647,files=links,runOnlyForDeploymentPostprocessing=0)
 phases=[ref('sources:'+key),ref('frameworks:'+key)]
 if key=='app':
  iconBuild=add('build:icon','PBXBuildFile',fileRef=icon)
  phases.append(add('resources:app','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[iconBuild],runOnlyForDeploymentPostprocessing=0))
  embed=add('embed:core','PBXBuildFile',fileRef=ref('product:core'),settings={'ATTRIBUTES':['CodeSignOnCopy','RemoveHeadersOnCopy']})
  phases.append(add('embed:app','PBXCopyFilesBuildPhase',buildActionMask=2147483647,dstPath='',dstSubfolderSpec=10,files=[embed],name='Embed Frameworks',runOnlyForDeploymentPostprocessing=0))
 add('target:'+key,'PBXNativeTarget',buildConfigurationList=ref('configs:'+key),buildPhases=phases,buildRules=[],dependencies=[] if key=='core' else ([ref('dependency:'+key),ref('dependency:apptestApp')] if key=='apptest' else [ref('dependency:'+key)]),name=name,productName=name,productReference=ref('product:'+key),productType={'core':'com.apple.product-type.framework','app':'com.apple.product-type.application','test':'com.apple.product-type.bundle.unit-test','apptest':'com.apple.product-type.bundle.unit-test'}[key])
for mode in ['Debug','Release']:
 add('config:project'+mode,'XCBuildConfiguration',buildSettings={'MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx'},name=mode)
add('configs:project','XCConfigurationList',buildConfigurations=[ref('config:project'+m) for m in ['Debug','Release']],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
add('products','PBXGroup',children=products,name='Products',sourceTree='<group>')
add('main','PBXGroup',children=[*sourcegroups.values(),config,ent,appinfo,icon,ref('products')],sourceTree='<group>')
add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600'},buildConfigurationList=ref('configs:project'),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=ref('main'),productRefGroup=ref('products'),projectDirPath='',projectRoot='',targets=[ref('target:'+k) for k in ['app','core','test','apptest']])
write('DuplicateFinder.xcodeproj/project.pbxproj','// !$*UTF8*$!\n'+render({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ref('project')}))
def buildable(key,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ID("target:"+key)}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:DuplicateFinder.xcodeproj"/>'
write('DuplicateFinder.xcodeproj/xcshareddata/xcschemes/DuplicateFinder.xcscheme',f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('app','DuplicateFinder.app')}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{buildable('test','DuplicateFinderCoreTests.xctest')}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{buildable('apptest','DuplicateFinderAppTests.xctest')}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildable('test','DuplicateFinderCoreTests.xctest')}</TestableReference><TestableReference skipped="NO">{buildable('apptest','DuplicateFinderAppTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('app','DuplicateFinder.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('app','DuplicateFinder.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
