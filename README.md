# Dotfiles

使用 chezmoi 管理配置，目前支持：

- Termux：使用 pkg 管理软件包。
- Windows：使用 Scoop 管理软件包。

## 安装

### Termux

```bash
curl -fsSL https://raw.githubusercontent.com/RandomNEET/dotfiles/main/install.sh | bash
```

### Windows

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
