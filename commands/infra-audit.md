---
description: 利用側プロジェクトの静的解析(複雑度制御)・重複コード検出・多OS CI導入状況を診断する
---

利用側プロジェクトの「壊れない仕組み」導入状況を診断してください。各チェックは独立に実行し、1項目の失敗が他の診断を止めないようにする。対象は TypeScript/JavaScript プロジェクトのルート直下のみ (モノレポの `packages/*` は対象外)。

**`aidd:doctor` との違い**: `doctor` は aidd 自身の導入状態を診断する。このコマンドは **利用側プロジェクト** の静的解析・重複検出・CI の導入状況を診断する。

**判定方法の限界**: ファイル存在と grep によるヒューリスティック判定であり、ESLint flat config の `extends` や共有設定経由で実際にはルールが有効なケースを検出できないことがある。判定結果は参考情報として扱うこと。

**チェック項目**:

1. **`package.json` の存在**: 存在しなければ「対象外 (Node.js プロジェクトではない)」として全項目スキップし終了する
2. **静的解析 (ESLint 複雑度制御)**: `.eslintrc*` / `eslint.config.*` の有無、および以下ルールの設定有無
   - `complexity`
   - `max-lines-per-function`
   - `max-depth`
   - `max-params`
   - `@typescript-eslint/no-explicit-any`
   - `sonarjs/cognitive-complexity`
   不足していれば参考値 (関数長60行 / 循環的複雑度20 / ネスト4 / パラメータ6) と導入例を提示する
3. **重複・未使用コード検出**: `package.json` の `devDependencies` に `jscpd` または `knip` があるか、`.github/workflows/*.yml` / `*.yaml` 内で実行されているか。未導入なら `npm i -D jscpd knip` と CI 設定例を提示する
4. **多OS CI**: `.github/workflows/*.yml` / `*.yaml` の `runs-on:` の値を収集し、`ubuntu-latest` のみなら折衷案 (PR時: ubuntu + macOS、Windows: daily/main push限定) を提示する

各項目を実行するには Bash tool で以下相当のコマンドを使う:

```bash
# 1. package.json 存在確認
if [ ! -f package.json ]; then
  echo "package.json: 対象外 (Node.js プロジェクトではない、以降スキップ)"
  exit 0
fi
echo "package.json: OK"

# 2. ESLint 複雑度制御ルール
if compgen -G ".eslintrc*" > /dev/null || compgen -G "eslint.config.*" > /dev/null; then
  echo "eslint config: OK"
  for rule in complexity max-lines-per-function max-depth max-params "@typescript-eslint/no-explicit-any" "sonarjs/cognitive-complexity"; do
    if [ "$rule" = "complexity" ]; then
      # bare "complexity" rule key, not a substring of e.g. "sonarjs/cognitive-complexity"
      grep -Eq -- '(^|[^A-Za-z-])"?complexity"?[[:space:]]*:' .eslintrc* eslint.config.* 2>/dev/null && echo "  $rule: OK" || echo "  $rule: 未導入 (参考値: 関数長60行/循環的複雑度20/ネスト4/パラメータ6)"
    else
      grep -q -- "$rule" .eslintrc* eslint.config.* 2>/dev/null && echo "  $rule: OK" || echo "  $rule: 未導入 (参考値: 関数長60行/循環的複雑度20/ネスト4/パラメータ6)"
    fi
  done
else
  echo "eslint config: 未導入 (.eslintrc.json や eslint.config.js の追加を検討)"
fi

# 3. 重複・未使用コード検出
if grep -q '"jscpd"\|"knip"' package.json 2>/dev/null; then
  echo "duplicate/unused detection: OK (devDependencies に jscpd/knip あり)"
else
  echo "duplicate/unused detection: 未導入 (npm i -D jscpd knip を検討)"
fi
workflow_files=()
while IFS= read -r -d '' f; do workflow_files+=("$f"); done < <(find .github/workflows -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null)
if [ ${#workflow_files[@]} -eq 0 ]; then
  echo "  CI統合: 対象外 (.github/workflows 内にワークフローファイルなし)"
elif grep -l 'jscpd\|knip' "${workflow_files[@]}" > /dev/null 2>&1; then
  echo "  CI統合: OK"
else
  echo "  CI統合: 未導入 (jscpd/knip を CI workflow に組み込むことを検討)"
fi

# 4. 多OS CI
if [ ${#workflow_files[@]} -gt 0 ]; then
  oses=$(grep -h 'runs-on:' "${workflow_files[@]}" 2>/dev/null | sort -u)
  echo "runs-on 一覧:"
  echo "$oses"
  if echo "$oses" | grep -q 'windows-latest\|macos-latest'; then
    echo "多OS CI: OK"
  else
    echo "多OS CI: ubuntu-latest のみ (折衷案: PR時は ubuntu-latest + macOS-latest、Windows は daily/main push限定での実行を検討)"
  fi
else
  echo "多OS CI: 対象外 (.github/workflows 内にワークフローファイルなし)"
fi
```

**出力**: 項目ごとに `OK` / `未導入` / `対象外` と、`未導入` には具体的な対処コマンド例を1〜2行付ける。最後に総合サマリ (未導入項目数) を1行で出す。
