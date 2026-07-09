#!/bin/bash

# 定义配置文件路径
CODEX_DIR="$HOME/.codex"
CONFIG_FILE="$CODEX_DIR/config.toml"
AUTH_FILE="$CODEX_DIR/auth.json"
LOCAL_SCRIPT="$CODEX_DIR/manage_codex.sh"

# 内置的 URL
URL1="https://anyrouter.top/v1"
URL2="https://pmpjfbhq.cn-nb1.rainapp.top/v1"

# 获取当前的 Shell 配置文件路径
get_shell_rc() {
    if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
        echo "$HOME/.zshrc"
    else
        echo "$HOME/.bashrc"
    fi
}

# 初始化配置文件（如果不存在的话）
init_files() {
    if [ ! -d "$CODEX_DIR" ]; then
        mkdir -p "$CODEX_DIR"
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "💡 未检测到 config.toml，正在创建初始配置..."
        cat <<EOF > "$CONFIG_FILE"
model = "gpt-5-codex"
model_provider = "anyrouter"
preferred_auth_method = "apikey"

[model_providers.anyrouter]
name = "Any Router"
base_url = "$URL1"
wire_api = "responses"
EOF
    fi

    if [ ! -f "$AUTH_FILE" ]; then
        echo "💡 未检测到 auth.json，正在创建初始配置..."
        echo '{"OPENAI_API_KEY":"YOUR_KEY_HERE"}' > "$AUTH_FILE"
    fi
}

# 1. 读取当前的 Key 和 URL（不脱敏，完全显示）
view_current_config() {
    echo "🔍 === 当前配置状态 ==="
    
    # 读取 URL
    if [ -f "$CONFIG_FILE" ]; then
        current_url=$(grep -E 'base_url[[:space:]]*=[[:space:]]*' "$CONFIG_FILE" | sed -E 's/.*base_url[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')
        echo "当前 Base URL: ${current_url:-'未设置'}"
    else
        echo "当前 Base URL: ❌ 配置文件 config.toml 不存在"
    fi

    # 读取 API Key（完整输出）
    if [ -f "$AUTH_FILE" ]; then
        if command -v node &> /dev/null; then
            current_key=$(node -e "const fs=require('fs'); console.log(JSON.parse(fs.readFileSync('$AUTH_FILE', 'utf8')).OPENAI_API_KEY);")
        else
            current_key=$(grep -oE '"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"[^"]+"' "$AUTH_FILE" | sed -E 's/.*"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        fi
        
        if [ -z "$current_key" ] || [ "$current_key" = "YOUR_KEY_HERE" ]; then
            echo "当前 API Key: ⚠️ 尚未配置有效 Key"
        else
            echo "当前 API Key: ${current_key}"
        fi
    else
        echo "当前 API Key: ❌ 配置文件 auth.json 不存在"
    fi
    echo "======================="
}

# 2. 替换 API Key
update_apikey() {
    read -p "请输入您新的 API Key (以 sk- 开头): " new_key
    if [ -z "$new_key" ]; then
        echo "❌ Key 不能为空！"
        return
    fi
    
    if command -v node &> /dev/null; then
        node -e "
        const fs = require('fs');
        const data = JSON.parse(fs.readFileSync('$AUTH_FILE', 'utf8'));
        data.OPENAI_API_KEY = '$new_key';
        fs.writeFileSync('$AUTH_FILE', JSON.stringify(data, null, 2));
        "
        echo "✅ API Key 已成功更新！"
    else
        sed -i.bak "s/\"OPENAI_API_KEY\":\".*\"/\"OPENAI_API_KEY\":\"$new_key\"/g" "$AUTH_FILE"
        echo "✅ API Key 已更新！"
    fi
}

# 3. 切换 URL
switch_url() {
    echo "请选择要切换的 base_url:"
    echo "1) $URL1 (默认 AnyRouter)"
    echo "2) $URL2 (备用 RainApp 端点)"
    read -p "请输入序号 [1 或 2]: " choice

    case $choice in
        1) target_url=$URL1 ;;
        2) target_url=$URL2 ;;
        *) echo "❌ 无效选择！"; return ;;
    esac

    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i "" "s|base_url = \".*\"|base_url = \"$target_url\"|g" "$CONFIG_FILE"
    else
        sed -i "s|base_url = \".*\"|base_url = \"$target_url\"|g" "$CONFIG_FILE"
    fi

    echo "✅ base_url 已成功切换为: $target_url"
}

# 4. 测试连通性与稳定性 (测延迟、算平均值、评估稳定性)
test_connectivity() {
    echo "正在测试 URL 连通性、延迟与稳定性 (每项测试 3 次)..."
    echo "------------------------------------------------------------"
    
    for url in "$URL1" "$URL2"; do
        echo "测试目标: $url"
        
        total_time=0
        success_count=0
        fail_count=0
        
        for i in {1..3}; do
            # 使用 curl 的 -w 参数精准抓取时间（单位：秒），设置 3 秒超时
            # time_connect: 建立 TCP 连接的时间
            # http_code: 状态码
            result=$(curl -o /dev/null -s -w "%{time_connect} %{http_code}" --connect-timeout 3 "$url")
            
            # 提取延迟和状态码
            delay_sec=$(echo $result | cut -d' ' -f1)
            status_code=$(echo $result | cut -d' ' -f2)
            
            # 将秒转换为毫秒 (保留整数)
            delay_ms=$(echo "$delay_sec * 1000" | awk '{print int($1)}')
            
            if [ "$status_code" -ne 000 ] && [ "$delay_ms" -gt 0 ]; then
                echo "  第 $i 次: 成功 | 延迟: ${delay_ms}ms | HTTP 状态码: $status_code"
                total_time=$((total_time + delay_ms))
                success_count=$((success_count + 1))
            else
                echo "  第 $i 次: ❌ 超时或连接失败"
                fail_count=$((fail_count + 1))
            fi
            sleep 0.2 # 稍作停顿
        done
        
        # 计算并输出统计结果
        if [ $success_count -gt 0 ]; then
            avg_delay=$((total_time / success_count))
            loss_rate=$((fail_count * 100 / 3))
            
            echo -n "📊 统计结果: 平均延迟: ${avg_delay}ms | 丢包率: ${loss_rate}% | 稳定性评估: "
            if [ $loss_rate -eq 0 ] && [ $avg_delay -lt 100 ]; then
                echo "🟢 极佳 (延迟低且稳定)"
            elif [ $loss_rate -eq 0 ] && [ $avg_delay -lt 300 ]; then
                echo "🟡 良好 (网络连通，延迟中等)"
            elif [ $loss_rate -gt 0 ] && [ $loss_rate -lt 100 ]; then
                echo "🟠 不稳定 (存在丢包/抖动)"
            else
                echo "🔴 极差 (延迟高或频繁超时)"
            fi
        else
            echo "📊 统计结果: ❌ 3次测试全部失败，该节点当前不可用！"
        fi
        echo "------------------------------------------------------------"
    done
}

# 5. 卸载配置文件 (~/.codex 内的 json/toml)
uninstall_config() {
    if [ ! -d "$CODEX_DIR" ]; then
        echo "⚠️ 未发现 $CODEX_DIR 目录，无需卸载。"
        return
    fi

    echo "⚠️ 警告：该操作将清理现有的 Codex 配置文件。"
    echo "1) 彻底删除整个 ~/.codex 目录 (含本地管理脚本)"
    echo "2) 仅仅删除配置文件 (保留当前管理脚本)"
    echo "3) 取消操作"
    read -p "请选择清理方式 [1-3]: " un_choice

    case $un_choice in
        1)
            read -p "确定要【彻底删除整个目录】吗？输入 y 确认: " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                rm -rf "$CODEX_DIR"
                echo "🗑️  ~/.codex 目录已彻底删除！"
            fi
            ;;
        2)
            rm -f "$CONFIG_FILE" "$AUTH_FILE"
            echo "🗑️  config.toml 和 auth.json 已清理，本地脚本仍保留。"
            ;;
        3|*)
            echo "已取消卸载操作。"
            ;;
    esac
}

# 6. 注册为本地快捷指令 bpgpt并固化脚本
register_shortcut() {
    mkdir -p "$CODEX_DIR"
    
    # 如果检测到是远程流执行（或者不是存放在指定目录的脚本），就固化一份到本地
    if [ "$0" = "bash" ] || [ ! -f "$LOCAL_SCRIPT" ]; then
        echo "📦 正在将当前运行的最新代码持久化保存到本地: $LOCAL_SCRIPT"
        # 抓取当前运行脚本的源码，如果是管道执行，则尝试克隆或需要用户从本地保存
        cat "$0" > "$LOCAL_SCRIPT" 2>/dev/null
        if [ $? -ne 0 ] || [ ! -s "$LOCAL_SCRIPT" ]; then
             echo "⚠️ 远程一键运行时无法直接用 \$0 复制源码。"
             echo "提示：请直接拷贝此脚本保存到 $LOCAL_SCRIPT 后再执行注册。"
             return
        fi
    fi
    
    chmod +x "$LOCAL_SCRIPT"
    SHELL_RC=$(get_shell_rc)

    # 检查是否已经注册过
    if grep -q "alias bpgpt=" "$SHELL_RC"; then
        echo "💡 快捷指令 'bpgpt' 已经存在于 $SHELL_RC 中，无需重复注册。"
    else
        echo "alias bpgpt=\"$LOCAL_SCRIPT\"" >> "$SHELL_RC"
        echo "✅ 快捷指令 'bpgpt' 已成功注册到 $SHELL_RC ！"
        echo "👉 请运行 'source $SHELL_RC' 或重启终端使指令生效。"
    fi
}

# 7. 彻底清理本地快捷方式和代码脚本
uninstall_shortcut_and_script() {
    echo "⚠️ 正在启动【快捷指令与脚本实体】卸载程序..."
    SHELL_RC=$(get_shell_rc)
    
    # 1. 移除 Alias 快捷方式
    if grep -q "alias bpgpt=" "$SHELL_RC"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i "" "/alias bpgpt=/d" "$SHELL_RC"
        else
            sed -i "/alias bpgpt=/d" "$SHELL_RC"
        fi
        echo "🗑️  已从 $SHELL_RC 中移除 'bpgpt' 快捷指令。"
        echo "👉 提示：当前终端缓存可能还在，重启终端或执行 'unalias bpgpt' 可立即生效。"
    else
        echo "💡 未在 $SHELL_RC 中发现 'bpgpt' 快捷指令，无需清理。"
    fi

    # 2. 移除脚本实体
    if [ -f "$LOCAL_SCRIPT" ]; then
        rm -f "$LOCAL_SCRIPT"
        echo "🗑️  已成功删除本地脚本实体: $LOCAL_SCRIPT"
    else
        echo "💡 本地未发现脚本实体文件。"
    fi
    
    echo "✅ 清理完毕！您现在可以放心去远程 curl 最新的代码了。"
    exit 0
}


# 主菜单循环
while true; do
    echo
    echo "=== Codex/AnyRouter 配置管理器 ==="
    echo "1. 查看当前 Key 和 URL 状态 (明文)"
    echo "2. 替换 API Key"
    echo "3. 切换 Base URL"
    echo "4. 测试内置 URL 连通性"
    echo "5. 卸载/清理配置文件 (toml/json)"
    echo "6. 将本脚本固化并注册为快捷指令 (bpgpt)"
    echo "7. ❌ 仅卸载本地快捷方式与脚本实体 (方便取最新代码)"
    echo "8. 退出"
    read -p "请选择操作 [1-8]: " menu_choice

    case $menu_choice in
        1) view_current_config ;;
        2) init_files; update_apikey ;;
        3) init_files; switch_url ;;
        4) test_connectivity ;;
        5) uninstall_config ;;
        6) register_shortcut ;;
        7) uninstall_shortcut_and_script ;;
        8) echo "再见！"; exit 0 ;;
        *) echo "❌ 输入错误，请重新选择" ;;
    esac
done
