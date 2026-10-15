#!/usr/bin/env bash

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLEANUP_SCRIPT="$SCRIPT_DIR/../src/cleanup.sh"
BASE_TEST_DIR="$SCRIPT_DIR/test_env"

cleanup_env() {
    rm -rf "$BASE_TEST_DIR"
}

trap cleanup_env EXIT

make_file() {
    local target_path="$1"
    local size_mb="$2"
    fallocate -l "${size_mb}M" "$target_path" 2>/dev/null || truncate -s "${size_mb}M" "$target_path" 2>/dev/null || dd if=/dev/zero of="$target_path" bs=1M count="$size_mb" status=none
}

run_test() {
    local name="$1"
    echo "=========================================="
    echo "Запуск теста: $name"
    echo "=========================================="
}

init_dirs() {
    rm -rf "$BASE_TEST_DIR"
    mkdir -p "$BASE_TEST_DIR/log" "$BASE_TEST_DIR/backup"
}

run_test "Тест 1: Заполнение ниже порога (очистка не требуется)"
init_dirs
make_file "$BASE_TEST_DIR/log/file1.log" 200
make_file "$BASE_TEST_DIR/log/file2.log" 200
make_file "$BASE_TEST_DIR/log/file3.log" 200
touch -d "10 minutes ago" "$BASE_TEST_DIR/log/file1.log"
touch -d "5 minutes ago" "$BASE_TEST_DIR/log/file2.log"
touch -d "1 minute ago" "$BASE_TEST_DIR/log/file3.log"

LOG_SIZE_MB=$(du -sm "$BASE_TEST_DIR/log" | awk '{print $1}')
echo "Размер папки логов: ${LOG_SIZE_MB} MB (требование >= 0.5 GB соблюдено)"

"$CLEANUP_SCRIPT" "$BASE_TEST_DIR/log" 70 "$BASE_TEST_DIR/backup" 1200

if [ $(ls -1 "$BASE_TEST_DIR/backup" 2>/dev/null | wc -l) -ne 0 ]; then
    echo "Ошибка: архив не должен был создаваться!" >&2
    exit 1
fi

if [ ! -f "$BASE_TEST_DIR/log/file1.log" ] || [ ! -f "$BASE_TEST_DIR/log/file2.log" ] || [ ! -f "$BASE_TEST_DIR/log/file3.log" ]; then
    echo "Ошибка: файлы не должны были удаляться!" >&2
    exit 1
fi
echo "Тест 1 успешно пройден!"

run_test "Тест 2: Заполнение выше порога (удаление старейшего файла, tar.gz)"
init_dirs
make_file "$BASE_TEST_DIR/log/app_old.log" 180
make_file "$BASE_TEST_DIR/log/app_mid1.log" 120
make_file "$BASE_TEST_DIR/log/app_mid2.log" 250
make_file "$BASE_TEST_DIR/log/app_new.log" 300
touch -d "20 minutes ago" "$BASE_TEST_DIR/log/app_old.log"
touch -d "15 minutes ago" "$BASE_TEST_DIR/log/app_mid1.log"
touch -d "10 minutes ago" "$BASE_TEST_DIR/log/app_mid2.log"
touch -d "1 minute ago" "$BASE_TEST_DIR/log/app_new.log"

LOG_SIZE_MB=$(du -sm "$BASE_TEST_DIR/log" | awk '{print $1}')
echo "Размер папки логов: ${LOG_SIZE_MB} MB (требование >= 0.5 GB соблюдено)"

"$CLEANUP_SCRIPT" "$BASE_TEST_DIR/log" 70 "$BASE_TEST_DIR/backup" 1000

ARCHIVE=$(ls -1 "$BASE_TEST_DIR/backup"/backup_*.tar.gz 2>/dev/null | head -n 1)
if [ -z "$ARCHIVE" ]; then
    echo "Ошибка: архив .tar.gz не найден!" >&2
    exit 1
fi

tar -tzf "$ARCHIVE" | grep -q "app_old.log" || { echo "Ошибка: старый файл отсутствует в архиве!" >&2; exit 1; }

if [ -f "$BASE_TEST_DIR/log/app_old.log" ]; then
    echo "Ошибка: старый файл не был удален из логов!" >&2
    exit 1
fi

if [ ! -f "$BASE_TEST_DIR/log/app_mid1.log" ] || [ ! -f "$BASE_TEST_DIR/log/app_new.log" ]; then
    echo "Ошибка: более свежие файлы были ошибочно удалены!" >&2
    exit 1
fi
echo "Тест 2 успешно пройден!"

run_test "Тест 3: Заполнение 90% при пороге 60% (удаление нескольких файлов по возрасту)"
init_dirs
make_file "$BASE_TEST_DIR/log/log_1.log" 150
make_file "$BASE_TEST_DIR/log/log_2.log" 200
make_file "$BASE_TEST_DIR/log/log_3.log" 250
make_file "$BASE_TEST_DIR/log/log_4.log" 300
touch -d "40 minutes ago" "$BASE_TEST_DIR/log/log_1.log"
touch -d "30 minutes ago" "$BASE_TEST_DIR/log/log_2.log"
touch -d "20 minutes ago" "$BASE_TEST_DIR/log/log_3.log"
touch -d "5 minutes ago" "$BASE_TEST_DIR/log/log_4.log"

LOG_SIZE_MB=$(du -sm "$BASE_TEST_DIR/log" | awk '{print $1}')
echo "Размер папки логов: ${LOG_SIZE_MB} MB (требование >= 0.5 GB соблюдено)"

"$CLEANUP_SCRIPT" "$BASE_TEST_DIR/log" 60 "$BASE_TEST_DIR/backup" 1000

ARCHIVE=$(ls -1 "$BASE_TEST_DIR/backup"/backup_*.tar.gz 2>/dev/null | head -n 1)
if [ -z "$ARCHIVE" ]; then
    echo "Ошибка: архив не найден!" >&2
    exit 1
fi

tar -tzf "$ARCHIVE" | grep -q "log_1.log" || { echo "Ошибка: log_1.log отсутствует в архиве!" >&2; exit 1; }
tar -tzf "$ARCHIVE" | grep -q "log_2.log" || { echo "Ошибка: log_2.log отсутствует в архиве!" >&2; exit 1; }

if [ -f "$BASE_TEST_DIR/log/log_1.log" ] || [ -f "$BASE_TEST_DIR/log/log_2.log" ]; then
    echo "Ошибка: файлы log_1 и log_2 не удалены!" >&2
    exit 1
fi

if [ ! -f "$BASE_TEST_DIR/log/log_3.log" ] || [ ! -f "$BASE_TEST_DIR/log/log_4.log" ]; then
    echo "Ошибка: файлы log_3 или log_4 были неверно удалены!" >&2
    exit 1
fi
echo "Тест 3 успешно пройден!"

run_test "Тест 4 (на 9 баллов): Сжатие LZMA при LAB1_MAX_COMPRESSION=1"
init_dirs
make_file "$BASE_TEST_DIR/log/data_old.log" 200
make_file "$BASE_TEST_DIR/log/data_mid.log" 300
make_file "$BASE_TEST_DIR/log/data_new.log" 300
touch -d "2 hours ago" "$BASE_TEST_DIR/log/data_old.log"
touch -d "1 hour ago" "$BASE_TEST_DIR/log/data_mid.log"
touch -d "10 minutes ago" "$BASE_TEST_DIR/log/data_new.log"

LOG_SIZE_MB=$(du -sm "$BASE_TEST_DIR/log" | awk '{print $1}')
echo "Размер папки логов: ${LOG_SIZE_MB} MB (требование >= 0.5 GB соблюдено)"

export LAB1_MAX_COMPRESSION=1
"$CLEANUP_SCRIPT" "$BASE_TEST_DIR/log" 70 "$BASE_TEST_DIR/backup" 1000
unset LAB1_MAX_COMPRESSION

LZMA_ARCHIVE=$(ls -1 "$BASE_TEST_DIR/backup"/backup_*.tar.lzma 2>/dev/null | head -n 1)
if [ -z "$LZMA_ARCHIVE" ]; then
    echo "Ошибка: архив формата .tar.lzma не создан!" >&2
    exit 1
fi

tar --lzma -tf "$LZMA_ARCHIVE" | grep -q "data_old.log" || { echo "Ошибка: data_old.log отсутствует в LZMA архиве!" >&2; exit 1; }

if [ -f "$BASE_TEST_DIR/log/data_old.log" ]; then
    echo "Ошибка: data_old.log не был удален!" >&2
    exit 1
fi
echo "Тест 4 успешно пройден!"

run_test "Тест 5 (Граничное значение): Ровно 70% заполнения при пороге 70%"
init_dirs
make_file "$BASE_TEST_DIR/log/boundary_1.log" 350
make_file "$BASE_TEST_DIR/log/boundary_2.log" 350

LOG_SIZE_MB=$(du -sm "$BASE_TEST_DIR/log" | awk '{print $1}')
echo "Размер папки логов: ${LOG_SIZE_MB} MB (требование >= 0.5 GB соблюдено)"

"$CLEANUP_SCRIPT" "$BASE_TEST_DIR/log" 70 "$BASE_TEST_DIR/backup" 1000

if [ $(ls -1 "$BASE_TEST_DIR/backup" 2>/dev/null | wc -l) -ne 0 ]; then
    echo "Ошибка: при равенстве порогу очистка производиться не должна!" >&2
    exit 1
fi
echo "Тест 5 успешно пройден!"

echo "=========================================="
echo "Все тесты успешно пройдены!"
echo "=========================================="
