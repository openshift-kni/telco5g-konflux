#!/usr/bin/env bash

# Exercise download-go-tool.sh with a fake Go command so network failures are
# deterministic and the retry count can be checked without contacting a proxy.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
download_script="${script_dir}/../download-go-tool.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/mock-bin"

cat > "$test_dir/mock-bin/go" <<'MOCK_GO'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
    version)
        if [[ "${2:-}" == -m ]]; then
            printf '\tmod\texample.com/fake-tool\tv1.2.3\n'
        else
            echo 'go version go1.26.3 linux/amd64'
        fi
        ;;
    mod)
        if [[ "$2" == init ]]; then
            : > go.mod
        fi
        ;;
    install)
        count=$(cat "$MOCK_COUNT_FILE" 2>/dev/null || echo 0)
        count=$((count + 1))
        echo "$count" > "$MOCK_COUNT_FILE"
        case "$MOCK_MODE" in
            proxy-once|sum-once)
                if [[ $count -eq 1 ]]; then
                    if [[ "$MOCK_MODE" == proxy-once ]]; then
                        endpoint=proxy.golang.org
                    else
                        endpoint=sum.golang.org
                    fi
                    echo "reading https://${endpoint}/test: stream error: stream ID 5; INTERNAL_ERROR; received from peer" >&2
                    exit 1
                fi
                ;;
            always-transient)
                echo 'stream error: stream ID 5; INTERNAL_ERROR; received from peer' >&2
                exit 1
                ;;
            checksum-mismatch)
                echo 'verifying module: checksum mismatch' >&2
                exit 1
                ;;
            invalid-module)
                echo 'module not found' >&2
                exit 1
                ;;
        esac
        printf '#!/bin/sh\nexit 0\n' > "$GOBIN/fake-tool"
        chmod +x "$GOBIN/fake-tool"
        ;;
esac
MOCK_GO
chmod +x "$test_dir/mock-bin/go"

# Avoid waiting through the backoff while still exercising every retry attempt.
printf '#!/bin/sh\nexit 0\n' > "$test_dir/mock-bin/sleep"
chmod +x "$test_dir/mock-bin/sleep"

run_case() {
    local mode="$1"
    local expected_status="$2"
    local expected_attempts="$3"
    local case_dir="$test_dir/$mode"
    mkdir -p "$case_dir"

    local status=0
    PATH="$test_dir/mock-bin:$PATH" MOCK_MODE="$mode" MOCK_COUNT_FILE="$case_dir/count" \
        "$download_script" --install-dir "$case_dir" fake-tool example.com/fake-tool@v1.2.3 \
        > "$case_dir/output" 2>&1 || status=$?

    if [[ ($expected_status == success && $status -ne 0) || ($expected_status == failure && $status -eq 0) ]]; then
        echo "$mode: unexpected exit status $status" >&2
        cat "$case_dir/output" >&2
        return 1
    fi
    if [[ $(cat "$case_dir/count") -ne $expected_attempts ]]; then
        echo "$mode: expected $expected_attempts go install attempts" >&2
        cat "$case_dir/output" >&2
        return 1
    fi
    if [[ $expected_status == success && ! -x "$case_dir/fake-tool" ]]; then
        echo "$mode: tool was not installed" >&2
        return 1
    fi
    echo "$mode: passed ($expected_attempts attempt(s))"
}

run_case proxy-once success 2
run_case sum-once success 2
run_case always-transient failure 4
run_case checksum-mismatch failure 1
run_case invalid-module failure 1
