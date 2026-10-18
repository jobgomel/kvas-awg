#!/bin/sh
# Unit and integration test suite for kvas-awg parser, decoding and logic
set -e

PASSED=0
FAILED=0

assert_eq() {
    expected="$1"
    actual="$2"
    test_name="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        FAILED=$((FAILED + 1))
    fi
}

assert_contains() {
    haystack="$1"
    needle="$2"
    test_name="$3"
    if echo "$haystack" | grep -F -q -- "$needle"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Pattern not found: '$needle'"
        FAILED=$((FAILED + 1))
    fi
}

assert_not_contains() {
    haystack="$1"
    needle="$2"
    test_name="$3"
    if ! echo "$haystack" | grep -F -q -- "$needle"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        echo "    Pattern unexpectedly found: '$needle'"
        FAILED=$((FAILED + 1))
    fi
}

assert_true() {
    cmd="$1"
    test_name="$2"
    if eval "$cmd"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        FAILED=$((FAILED + 1))
    fi
}

assert_false() {
    cmd="$1"
    test_name="$2"
    if ! eval "$cmd"; then
        echo "  [PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $test_name"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== Running kvas-awg test suite ==="

TMP_DIR=$(mktemp -d /tmp/kvas-awg-tests.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# --------------------------------------------------------------------------
# Test 1: Base64URL decoding with padding normalization
# --------------------------------------------------------------------------
echo "Test Group 1: Base64 / URL-Safe Base64 / Padding normalization"

decode_url_payload() {
    CLEAN_STR=$(echo "$1" | tr -d ' \t\r\n')
    case "$CLEAN_STR" in
        vpn://*|awg://*|amnezia://*|wireguard://*)
            B64_PAYLOAD="${CLEAN_STR#*://}"
            ;;
        *)
            B64_PAYLOAD="$CLEAN_STR"
            ;;
    esac

    # Нормализация URL-Safe Base64 в стандартный Base64 (_ -> /, - -> +)
    B64_PAYLOAD=$(echo "$B64_PAYLOAD" | tr '_-' '/+')

    # Дополнение паддинга '=' до кратности 4
    MOD=$((${#B64_PAYLOAD} % 4))
    if [ "$MOD" -eq 2 ]; then
        B64_PAYLOAD="${B64_PAYLOAD}=="
    elif [ "$MOD" -eq 3 ]; then
        B64_PAYLOAD="${B64_PAYLOAD}="
    fi

    echo "$B64_PAYLOAD" | base64 -d 2>/dev/null || true
}

SAMPLE_CONF="[Interface]
Address = 10.8.0.2/32
PrivateKey = aaaaaa=

[Peer]
PublicKey = bbbbbb=
Endpoint = 198.51.100.1:51820"

# Standard base64
STD_B64=$(echo "$SAMPLE_CONF" | base64 | tr -d '\r\n')
RESULT_STD=$(decode_url_payload "$STD_B64")
assert_contains "$RESULT_STD" "[Interface]" "Standard Base64 contains [Interface]"
assert_contains "$RESULT_STD" "[Peer]" "Standard Base64 contains [Peer]"

# vpn:// prefix + URL-safe (_ and -) + stripped padding '='
URLSAFE_B64=$(echo "$SAMPLE_CONF" | base64 | tr -d '\r\n=' | tr '/+' '_-')
RESULT_URLSAFE=$(decode_url_payload "vpn://${URLSAFE_B64}")
assert_contains "$RESULT_URLSAFE" "[Interface]" "vpn:// prefix with URL-Safe Base64 without padding decoded"
assert_contains "$RESULT_URLSAFE" "PrivateKey = aaaaaa=" "Payload values preserved correctly"

# awg:// prefix
RESULT_AWG=$(decode_url_payload "awg://${URLSAFE_B64}")
assert_contains "$RESULT_AWG" "[Interface]" "awg:// prefix handled"

# amnezia:// prefix
RESULT_AMN=$(decode_url_payload "amnezia://${URLSAFE_B64}")
assert_contains "$RESULT_AMN" "[Interface]" "amnezia:// prefix handled"

# --------------------------------------------------------------------------
# Test 2: Detection of Amnezia zlib container (AA...)
# --------------------------------------------------------------------------
echo "Test Group 2: Amnezia zlib-compressed container detection"

is_amnezia_zlib() {
    input="$1"
    clean=$(echo "$input" | tr -d ' \t\r\n')
    case "$clean" in
        vpn://*|awg://*) payload="${clean#*://}" ;;
        *) payload="$clean" ;;
    esac
    if echo "$payload" | grep -qE '^AA' || echo "$input" | grep -qE '^(vpn|awg)://AA'; then
        return 0
    fi
    return 1
}

assert_true "is_amnezia_zlib 'vpn://AAEAAQA...'" "vpn://AA... recognized as Amnezia zlib"
assert_true "is_amnezia_zlib 'awg://AAABBBCCC'" "awg://AA... recognized as Amnezia zlib"
assert_true "is_amnezia_zlib 'AAxyz123'" "Raw AA... recognized as Amnezia zlib"
assert_false "is_amnezia_zlib 'vpn://W0ludGVyZmFjZQo...'" "Legitimate config not flagged as Amnezia zlib"

# --------------------------------------------------------------------------
# Test 3: INI section filtering (awk stripping of [Socks5] and [Http])
# --------------------------------------------------------------------------
echo "Test Group 3: Awk INI section cleaner"

strip_proxy_sections() {
    awk '
        BEGIN { skip=0 }
        tolower($0) ~ /^\[(socks5|http)\]/ { skip=1 }
        skip && /^\[/ && tolower($0) !~ /^\[(socks5|http)\]/ { skip=0 }
        !skip { print }
    '
}

RAW_INPUT="[Interface]
Address = 10.8.0.2/32
PrivateKey = priv=
Jc = 4
Jmin = 40
Jmax = 70

[Socks5]
BindAddress = 127.0.0.1:9999

[Http]
BindAddress = 127.0.0.1:8888

[Peer]
PublicKey = pub=
Endpoint = 1.2.3.4:51820
AllowedIPs = 0.0.0.0/0
"

FILTERED=$(echo "$RAW_INPUT" | strip_proxy_sections)
assert_contains "$FILTERED" "[Interface]" "Keeps [Interface] section"
assert_contains "$FILTERED" "Jc = 4" "Keeps AWG params"
assert_contains "$FILTERED" "[Peer]" "Keeps [Peer] section"
assert_contains "$FILTERED" "Endpoint = 1.2.3.4:51820" "Keeps Peer endpoint"
assert_not_contains "$FILTERED" "[Socks5]" "Strips existing [Socks5]"
assert_not_contains "$FILTERED" "127.0.0.1:9999" "Strips old Socks5 bind address"
assert_not_contains "$FILTERED" "[Http]" "Strips existing [Http]"
assert_not_contains "$FILTERED" "127.0.0.1:8888" "Strips old Http bind address"

# --------------------------------------------------------------------------
# Test 4: IP validation regex from test_connection.sh
# --------------------------------------------------------------------------
echo "Test Group 4: IP validation helper"

is_valid_ip() {
    echo "$1" | grep -q -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'
}

assert_true "is_valid_ip '1.1.1.1'" "IPv4 1.1.1.1 is valid"
assert_true "is_valid_ip '130.49.161.82'" "IPv4 130.49.161.82 is valid"
assert_true "is_valid_ip '127.0.0.1'" "IPv4 127.0.0.1 is valid"
assert_true "is_valid_ip '2001:db8::1'" "IPv6 2001:db8::1 is valid"
assert_false "is_valid_ip ''" "Empty IP is invalid"
assert_false "is_valid_ip 'abc'" "Hostname is invalid"
assert_false "is_valid_ip '500 Internal Server Error'" "HTTP error body is invalid"
assert_false "is_valid_ip '1.2.3.4.5'" "5 octet IP is invalid"

# --------------------------------------------------------------------------
# Test 5: update_env_var helper
# --------------------------------------------------------------------------
echo "Test Group 5: update_env_var helper"

TEST_ENV="$TMP_DIR/env.sh"
cat << 'EOF' > "$TEST_ENV"
#!/bin/sh
PROXY_LOCAL_IP="127.0.0.1"
PROXY_LOCAL_PORT_SOCKS=10818
RESOURCE_PROFILE="balanced"
GOMEMLIMIT="24MiB"
EOF

update_env_var() {
    VAR_NAME="$1"
    VAR_VAL="$2"
    if grep -q "^[[:space:]]*${VAR_NAME}=" "$TEST_ENV"; then
        sed -i "s|^[[:space:]]*${VAR_NAME}=.*|${VAR_NAME}=${VAR_VAL}|" "$TEST_ENV"
    else
        echo "${VAR_NAME}=${VAR_VAL}" >> "$TEST_ENV"
    fi
}

update_env_var "GOMEMLIMIT" '"48MiB"'
update_env_var "RESOURCE_PROFILE" '"perf"'
update_env_var "LOG_LEVEL" '"silent"'

assert_contains "$(cat "$TEST_ENV")" 'GOMEMLIMIT="48MiB"' "Existing variable updated"
assert_contains "$(cat "$TEST_ENV")" 'RESOURCE_PROFILE="perf"' "Existing profile updated"
assert_contains "$(cat "$TEST_ENV")" 'LOG_LEVEL="silent"' "New variable appended"
assert_contains "$(cat "$TEST_ENV")" 'PROXY_LOCAL_PORT_SOCKS=10818' "Untouched variable preserved"

# --------------------------------------------------------------------------
# Test 6: MIPS byte-order detection (LSB vs MSB)
# --------------------------------------------------------------------------
echo "Test Group 6: MIPS Endianness detection via ELF header"

detect_mips_endian() {
    file="$1"
    ENDIAN_BYTE=$(dd if="$file" bs=1 count=1 skip=5 2>/dev/null | od -b 2>/dev/null | awk 'NR==1 {print $2}')
    if [ "$ENDIAN_BYTE" = "002" ] || [ "$ENDIAN_BYTE" = "2" ]; then
        echo "mips"
    else
        echo "mipsle"
    fi
}

MIPSLE_BIN="$TMP_DIR/dummy_mipsle"
MIPS_BIN="$TMP_DIR/dummy_mips"

# ELF header: \177 E L F + byte 4: EI_CLASS (1=32bit) + byte 5: EI_DATA (1=LSB, 2=MSB)
printf '\177ELF\001\001\000\000\000\000\000\000\000\000\000\000' > "$MIPSLE_BIN"
printf '\177ELF\001\002\000\000\000\000\000\000\000\000\000\000' > "$MIPS_BIN"

assert_eq "mipsle" "$(detect_mips_endian "$MIPSLE_BIN")" "Byte 5 = 1 detected as mipsle (little-endian)"
assert_eq "mips" "$(detect_mips_endian "$MIPS_BIN")" "Byte 5 = 2 detected as mips (big-endian)"

# --------------------------------------------------------------------------
# Test 7: Hardware profile selection logic
# --------------------------------------------------------------------------
echo "Test Group 7: Hardware profile selection"

detect_profile_mock() {
    TOTAL_MEM_MB="$1"
    CPUS="$2"
    if [ "$TOTAL_MEM_MB" -gt 0 ] && [ "$TOTAL_MEM_MB" -le 270 ] || [ "$CPUS" -le 1 ]; then
        echo "eco"
    elif [ "$TOTAL_MEM_MB" -ge 700 ] && [ "$CPUS" -ge 3 ]; then
        echo "perf"
    else
        echo "balanced"
    fi
}

assert_eq "eco" "$(detect_profile_mock 128 2)" "128MB RAM -> eco"
assert_eq "eco" "$(detect_profile_mock 256 1)" "1 CPU -> eco"
assert_eq "perf" "$(detect_profile_mock 1024 4)" "1024MB RAM + 4 CPU -> perf"
assert_eq "perf" "$(detect_profile_mock 768 4)" "768MB RAM + 4 CPU -> perf"
assert_eq "balanced" "$(detect_profile_mock 512 2)" "512MB RAM + 2 CPU -> balanced"

# --------------------------------------------------------------------------
# Test 8: MTU extraction and fallback logic
# --------------------------------------------------------------------------
echo "Test Group 8: MTU extraction and validation"

extract_mtu() {
    _conf="$1"
    _val=$(awk -F '=' '
        tolower($1) ~ /^[[:space:]]*mtu[[:space:]]*$/ {
            gsub(/[[:space:]]/, "", $2)
            print $2
            exit
        }
    ' "$_conf" 2>/dev/null)
    case "$_val" in
        ''|*[!0-9]*) echo "${2:-1376}" ;;
        *) echo "$_val" ;;
    esac
}

CONF_WITH_MTU="$TMP_DIR/with_mtu.conf"
cat << 'EOF' > "$CONF_WITH_MTU"
[Interface]
Address = 10.8.0.2/32
MTU = 1376
PrivateKey = abc=
EOF

CONF_NO_MTU="$TMP_DIR/no_mtu.conf"
cat << 'EOF' > "$CONF_NO_MTU"
[Interface]
Address = 10.8.0.2/32
PrivateKey = abc=
EOF

CONF_LOWER_MTU="$TMP_DIR/lower_mtu.conf"
cat << 'EOF' > "$CONF_LOWER_MTU"
[Interface]
mtu= 1280 
PrivateKey = abc=
EOF

assert_eq "1376" "$(extract_mtu "$CONF_WITH_MTU" 1420)" "Extracts MTU=1376 from config"
assert_eq "1420" "$(extract_mtu "$CONF_NO_MTU" 1420)" "Uses fallback 1420 when MTU missing"
assert_eq "1280" "$(extract_mtu "$CONF_LOWER_MTU" 1376)" "Handles lowercase mtu= with spaces"

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo ""
echo "=== Test Summary ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ "$FAILED" -eq 0 ]; then
    echo "ALL TESTS PASSED!"
    exit 0
else
    echo "SOME TESTS FAILED!"
    exit 1
fi
