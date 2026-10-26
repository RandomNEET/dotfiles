# Dotfiles

使用 chezmoi 管理配置，目前支持：

- Termux：使用 pkg 管理软件包
- Windows：使用 Scoop 管理软件包

配置由 chezmoi 直接写入各程序使用的路径

## 安装

默认将仓库保存到 `~/.local/share/dotfiles`

### Termux

```bash
curl -fsSL https://raw.githubusercontent.com/RandomNEET/dotfiles/main/install.sh | bash
```

### Windows

将 Scoop 的 `persist` 目录链接到 `~/.config`，其他配置由 chezmoi 直接部署到各程序使用的路径

已有 persist 数据会合并到 `.config`，同名文件保留 `.config` 中的版本，原 persist 目录保留为 `persist.before-dotfiles-*`

```powershell
Set-ExecutionPolicy -Scope Process Bypass
Invoke-WebRequest https://raw.githubusercontent.com/RandomNEET/dotfiles/main/install.ps1 -OutFile "$env:TEMP\dotfiles-install.ps1"
& "$env:TEMP\dotfiles-install.ps1"
```

### 从本地仓库安装

在仓库根目录执行，跳过拉取远程更新：

Termux：

```bash
bash install.sh --skip-update
```

Windows：

```powershell
.\install.ps1 -SkipUpdate
```

## 使用

```bash
chezmoi diff                 # 预览配置差异
chezmoi apply                # 应用配置
chezmoi update               # 拉取仓库更新并应用
chezmoi edit <目标文件>       # 编辑受管理的配置
chezmoi add <目标文件>        # 将本地配置保存到源目录
```

已有配置先用 `chezmoi diff` 查看，冲突按 chezmoi 提示处理
