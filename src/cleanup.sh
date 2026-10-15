#!/usr/bin/env bash

set -e

LOG_DIR="${1:-./log}"
THRESHOLD="${2:-70}"
BACKUP_DIR="${3:-./backup}"
TOTAL_MB="${4:-${LOG_MAX_SIZE_MB:-}}"

if [ ! -d "$LOG_DIR" ]; then
    echo "Ошибка: директория '$LOG_DIR' не найдена." >&2
    exit 1
fi

if [ -z "$TOTAL_MB" ]; then
    TOTAL_KB=$(df -k "$LOG_DIR" | awk 'NR==2 {print $2}')
else
    TOTAL_KB=$((TOTAL_MB * 1024))
fi

CURRENT_KB=$(du -sk "$LOG_DIR" | awk '{print $1}')
PERCENT=$((CURRENT_KB * 100 / TOTAL_KB))

echo "Папка логов: $LOG_DIR"
echo "Текущий объем: $CURRENT_KB KB из $TOTAL_KB KB ($PERCENT%)"
echo "Установленный порог: $THRESHOLD%"

if [ "$PERCENT" -le "$THRESHOLD" ]; then
    echo "Порог не превышен. Архивация не требуется."
    exit 0
fi

TARGET_KB=$((TOTAL_KB * THRESHOLD / 100))
NEED_TO_FREE_KB=$((CURRENT_KB - TARGET_KB))
echo "Порог превышен! Требуется освободить минимум: $NEED_TO_FREE_KB KB"

FILES_TO_ARCHIVE=()
FREED_KB=0

while IFS= read -r file; do
    [ -z "$file" ] && continue
    FILE_PATH="$LOG_DIR/$file"
    if [ -f "$FILE_PATH" ]; then
        FILE_KB=$(du -k "$FILE_PATH" | awk '{print $1}')
        FILES_TO_ARCHIVE+=("$file")
        FREED_KB=$((FREED_KB + FILE_KB))
        if [ "$FREED_KB" -ge "$NEED_TO_FREE_KB" ]; then
            break
        fi
    fi
done < <(ls -tr "$LOG_DIR")

if [ "${#FILES_TO_ARCHIVE[@]}" -eq 0 ]; then
    echo "Нет доступных файлов для архивации."
    exit 0
fi

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ "${LAB1_MAX_COMPRESSION:-0}" = "1" ]; then
    ARCHIVE_NAME="backup_${TIMESTAMP}.tar.lzma"
    tar --lzma -cf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$LOG_DIR" "${FILES_TO_ARCHIVE[@]}"
else
    ARCHIVE_NAME="backup_${TIMESTAMP}.tar.gz"
    tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$LOG_DIR" "${FILES_TO_ARCHIVE[@]}"
fi

for file in "${FILES_TO_ARCHIVE[@]}"; do
    rm -f "$LOG_DIR/$file"
done

NEW_KB=$(du -sk "$LOG_DIR" | awk '{print $1}')
NEW_PERCENT=$((NEW_KB * 100 / TOTAL_KB))

echo "Архив успешно создан: $BACKUP_DIR/$ARCHIVE_NAME"
echo "Удалено файлов: ${#FILES_TO_ARCHIVE[@]}"
echo "Освобождено памяти: $FREED_KB KB"
echo "Текущий объем после очистки: $NEW_KB KB из $TOTAL_KB KB ($NEW_PERCENT%)"
