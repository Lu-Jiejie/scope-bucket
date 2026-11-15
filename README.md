# scope-bucket

个人自用的 Scoop bucket，桶名 `lu`。

```
bucket/          清单，扁平存放
deprecated/      已下架的清单
bin/             checkver/checkhashes 等脚本 + 校验脚本
lib/             redirect.ps1
```

## 加一个应用

1. 新建 `bucket/<app>.json`（照抄 `zoxide.json` 改）。
2. `.\bin\checkhashes.ps1 <app> -Update`
3. `.\bin\checkver.ps1 <app>`

## 更新版本

`update.ps1` 只改清单里的版本号，这就是要推到 GitHub 的内容：

```
.\bin\update.ps1              # 改清单、校验、打印 diff，然后停下
.\bin\update.ps1 -Commit      # 改清单、校验、提交
.\bin\update.ps1 -Push        # 改清单、校验、提交、推送
.\bin\update.ps1 -Preview     # 只报告改了哪些，然后撤销改动
.\bin\update.ps1 -Install     # 顺带升级本机已装的程序
```

不带参数时改动留在工作区，先看过再执行 `-Commit`；`-Commit` 会接住上一次运行
留下的改动。`-Install` 会先 `git pull` 本地克隆再 `scoop update lu/<app>`，不加就
只动清单、不动本机。CI 每 2 小时跑一次同样的检查并自动提交。

## 下架一个应用

把清单移到 `deprecated/`。

## 数据不在应用目录里的情况

有些应用把数据硬写在 C 盘，用 `redirect.ps1` 把它链接到 `persist`：

```json
"pre_install": [
    "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Setup -Paths \"$env:APPDATA\\Vendor\\App\""
],
"pre_uninstall": [
    "& \"$bucketsdir\\$bucket\\lib\\redirect.ps1\" -Teardown"
]
```

`-Paths` 接受任意绝对路径，目标默认推导到 `$persist_dir` 下；写成
`"源路径 => 相对目录"` 可以自己指定。查看现状：

```
pwsh lib\redirect.ps1 -List -PersistDir <persist 目录>
```

## 本地测试

把仓库路径换成你自己的：

```
scoop bucket add lu file:///D:/path/to/scope-bucket
```

仓库至少要有一个提交才能被 `bucket add`。改完之后在桶目录里
`git pull --ff-only` 同步。

装的时候写全名（`scoop install lu/zoxide`）——`main` 里也有 `zoxide`，裸名会解析到它。
