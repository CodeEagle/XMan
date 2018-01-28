# XMan

Lightly tool that automatic integrating frameworks managed by `Carthage` or  `Punic` to your Xcode project


# Features
- Automatic copy frameworks configure in `xman.yaml` for every target (`Framework` | `Application` | `UniTests`)
- Automatic add `Run Script` to copy frameworks for `Application` target
- Automatic add `Copy File Phase` for `UniTests` target
- Can handle `Xcode 9` and `Xcode 8` project format

# Installtion
```
git clone git@github.com:CodeEagle/XMan.git
cd XMan
make install
```

# Usage
```
xman help
//with direcotry that contain `xman.yaml`, just run `xman`
```

# xman.yaml

Using xman.yaml to configure your project

`project` : "path/to/your/xcodeproj"
> if not config, will get first xcodeproj in directory

`carthage_folder` : "./Carthage"
> if not config, will be the `Carthage` folder in directory

`framework_copy_tool` : "/usr/local/bin/punic"
> if not config, will using `/usr/local/bin/carthage`

`deployment_target` : "8.0"
> for project

`carthage_frameworks` :
> custom framework array

```
  - Alamofire
```
> framework name in `Carthage/Build/iOS` without `.framework`

`target_configuration` :

      - Demo : #project name
        deployment_target: "9.0" # for target
        common_frameworks_key: "carthage_frameworks" # custom framework key
        frameworks:
          - AlamofireImage # extra framewrok



# Wanna speed up App launch time?

[RocketBoot](https://github.com/CodeEagle/RocketBoot)! here for you
