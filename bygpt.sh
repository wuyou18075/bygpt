mkdir -p ~/.codex && cat << 'EOF' > ~/.codex/manage_codex.sh
#!/bin/bash

# 定义配置文件路径
CODEX_DIR="$HOME/.codex"
CONFIG_FILE="$CODEX_DIR/config.toml"
AUTH_FILE="$CODEX_DIR/auth.json"
LOCAL_SCRIPT="$CODEX_DIR/manage_codex.sh"

# 内置的 URL（去掉了末尾的 /v1）
URL1="https://anyrouter.top"
URL2="https://pmpjfbhq.cn-nb1.rainapp.top"

get_shell_rc() {
    if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then echo "$HOME/.zshrc"; else echo "$HOME/.bashrc"; fi
}

init_files() {
    if [ ! -d "$CODEX_DIR" ]; then mkdir -p "$CODEX_DIR"; fi
    if [ ! -f "$CONFIG_FILE" ]; then
        cat <<EOM > "$CONFIG_FILE"
model = "gpt-5-codex"
model_provider = "anyrouter"
preferred_auth_method = "apikey"

[model_providers.anyrouter]
name = "Any Router"
base_url = "$URL1"
wire_api = "responses"
EOM
    fi
    if [ ! -f "$AUTH_FILE" ]; then echo '{"OPENAI_API_KEY":"YOUR_KEY_HERE"}' > "$AUTH_FILE"; fi
}

view_current_config() {
    echo "🔍 === 当前配置状态 ==="
    if [ -f "$CONFIG_FILE" ]; then
        current_url=$(grep -E 'base_url[[:space:]]*=[[:space:]]*' "$CONFIG_FILE" | sed -E 's/.*base_url[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')
        echo "当前 Base URL: ${current_url:-'未设置'}"
    else
        echo "当前 Base URL: ❌ config.toml 不存在"
    fi
    if [ -f "$AUTH_FILE" ]; then
        if command -v node &> /dev/null; then
            current_key=$(node -e "const fs=require('fs'); console.log(JSON.parse(fs.readFileSync('$AUTH_FILE', 'utf8')).OPENAI_API_KEY);")
        else
            current_key=$(grep -oE '"OPENAI_API_KEY"[[:space:]]*:[[:space:]]*"[^"]+"' "$AUTH_FILE" | sed -E 's/.*"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
        fi
        echo "当前 API Key: ${current_key:-'⚠️ 尚未配置有效 Key'}"
    else
        echo "当前 API Key: ❌ auth.json 不存在"
    fi
    echo "======================="
}

update_apikey() {
    read -p "请输入您新的 API Key (以 sk- 开头): " new_key
    if [ -z "$new_key" ]; then echo "❌ Key 不能为空！"; return; fi
    if command -v node &> /dev/null; then
        node -e "const fs = require('fs'); const data = JSON.parse(fs.readFileSync('$AUTH_FILE', 'utf8')); data.OPENAI_API_KEY = '$new_key'; fs.writeFileSync('$AUTH_FILE', JSON.stringify(data, null, 2));"
    else
        sed -i.bak "s/\"OPENAI_API_KEY\":\".*\"/\"OPENAI_API_KEY\":\"$new_key\"/g" "$AUTH_FILE"
    fi
    echo "✅ API Key 已成功更新！"
}

switch_url() {
    echo "请选择要切换的 base_url (自动剔除末尾 /v1):"
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

test_connectivity() {
    echo "正在测试 URL 连通性与稳定性 (每项测试 3 次)..."
    echo "------------------------------------------------------------"
    for url in "$URL1" "$URL2"; do
        test_url="${url}/v1"
        echo "测试目标: $test_url"
        total_time=0; success_count=0; fail_count=0
        for i in {1..3}; do
            result=$(curl -o /dev/null -s -w "%{time_connect} %{http_code}" --connect-timeout 3 "$test_url")
            delay_sec=$(echo $result | cut -d' ' -f1)
            status_code=$(echo $result | cut -d' ' -f2)
            delay_ms=$(echo "$delay_sec * 1000" | awk '{print int($1)}')
            if [ "$status_code" -ne 000 ] && [ "$delay_ms" -gt 0 ]; then
                echo "  第 $i 次: 成功 | 延迟: ${delay_ms}ms | 状态码: $status_code"
                total_time=$((total_time + delay_ms)); success_count=$((success_count + 1))
            else
                echo "  第 $i 次: ❌ 超时或连接失败"
                fail_count=$((fail_count + 1))
            fi
            sleep 0.1
        done
        if [ $success_count -gt 0 ]; then
            avg_delay=$((total_time / success_count)); loss_rate=$((fail_count * 100 / 3))
            echo "📊 平均延迟: ${avg_delay}ms | 丢包率: ${loss_rate}%"
        else
            echo "📊 统计结果: ❌ 该节点当前完全不可用"
        fi
        echo "------------------------------------------------------------"
    done
}

uninstall_config() {
    rm -f "$CONFIG_FILE" "$AUTH_FILE" && echo "🗑️  已清理 json/toml 配置文件。"
}

register_shortcut() {
    chmod +x "$LOCAL_SCRIPT"
    SHELL_RC=$(get_shell_rc)
    if grep -q "alias bpgpt=" "$SHELL_RC"; then
        echo "💡 'bpgpt' 快捷指令已存在。"
    else
        echo "alias bpgpt=\"$LOCAL_SCRIPT\"" >> "$SHELL_RC"
        echo "✅ 快捷指令 'bpgpt' 注册成功！请执行 'source $SHELL_RC' 生效。"
    fi
}

uninstall_shortcut_and_script() {
    SHELL_RC=$(get_shell_rc)
    if [[ "$OSTYPE" == "darwin"* ]]; then sed -i "" "/alias bpgpt=/d" "$SHELL_RC"; else sed -i "/alias bpgpt=/d" "$SHELL_RC"; fi
    rm -f "$LOCAL_SCRIPT"
    echo "🗑️  已卸载快捷指令与管理脚本本体。"
    exit 0
}

# 确保初次运行创建目录结构
init_files

# 主循环入口
while true; do
    echo -e "\n=== Codex/AnyRouter 配置管理器 ==="
    echo "1. 查看当前 Key 和 URL 状态 (明文)"
    echo "2. 替换 API Key"
    echo "3. 切换 Base URL (不带v1)"
    echo "4. 测试内置 URL 连通性与延迟"
    echo "5. 卸载/清理配置文件 (toml/json)"
    echo "6. 将本脚本固化并注册为快捷指令 (bpgpt)"
    echo "7. ❌ 仅卸载本地快捷方式与脚本实体"
    echo "8. 退出"
    read -p "请选择操作 [1-8]: " menu_choice
    case $menu_choice in
        1) view_current_config ;;
        2) update_apikey ;;
        3) switch_url ;;
        4) test_connectivity ;;
        5) uninstall_config ;;
        6) register_shortcut ;;
        7) uninstall_shortcut_and_script ;;
        8) exit 0 ;;
        *) echo "❌ 输入错误" ;;
    esac
done
EOF
chmod +x ~/.codex/manage_codex.sh
~ ~/.codex/manage_codex.sh
