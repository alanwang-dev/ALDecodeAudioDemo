platform :ios, '8.0'
#use_frameworks!
install! 'cocoapods',
:deterministic_uuids => false

############## common dependence libs source ###############
def pod_libksygpulive
    dep_path = ENV['KSYLIVEDEP_DIR']
    demo_path = ENV['KSYLIVEDEMO_DIR']
    
    pod 'GPUImage'
    #    pod 'libksygpulive/GPUImage',           :path => dep_path
    pod 'libksygpulive/yuv',                :path => dep_path
    pod 'libksygpulive/base',               :path => dep_path
    pod 'libksygpulive/mediacore_enc_265',  :path => dep_path
    
    #    pod 'libksygpulive/KSYStreameriOSSDK',          :path => demo_path
    pod 'KSYStreameriOSSDK',      :path => (dep_path)+'../KSYStreameriOSSDK'
    
    #    pod 'libksygpulive/networkAdaptor',          :path => demo_path
    pod 'networkAdaptor',             :path => (dep_path)+'../networkAdaptor'
    
#    pod 'ksylivekits/KSYStreamerEngine_iOS',      :path => demo_path
    pod 'KSYStreamerEngine',  :path => (dep_path)+'../KSYStreamerEngine_iOS'

    pod 'KSYCommon', :path => (dep_path)+'../KSYCommon'
    pod 'KSYGPUFilter',  :path => (dep_path)+'../KSYGPUFilter_iOS'
    pod 'ksylivekits/player', :path => demo_path
    pod 'ksylivekits/kits',   :path => demo_path
end

target 'ALDecodeAudio' do

pod_libksygpulive

end
