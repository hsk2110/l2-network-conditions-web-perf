import csv
import sys
from pathlib import Path
from datetime import datetime


def parse_file(filename: Path):
    fmt = "%m-%d-%Y %H:%M:%S"
    start_time = None
    download_time = None
    upload_time = None
    end_time = None

    with open(filename, "r", encoding="utf-8") as file:
        for raw_line in file:
            line = raw_line.strip()

            if "UTC Go Responsiveness to" in line:
                parts = line.split()
                start_time = datetime.strptime(f"{parts[0]} {parts[1]}", fmt)

            elif line.startswith("Download phase finished at"):
                download_time = datetime.strptime(line.split("at ", 1)[1].strip(), fmt)

            elif line.startswith("Upload phase finished at"):
                upload_time = datetime.strptime(line.split("at ", 1)[1].strip(), fmt)

            elif "UTC Go Responsiveness Finished" in line:
                parts = line.split()
                end_time = datetime.strptime(f"{parts[0]} {parts[1]}", fmt)

    if not all([start_time, download_time, upload_time, end_time]):
        return None

    download_duration = (download_time - start_time).total_seconds()
    upload_duration = (upload_time - download_time).total_seconds()
    packets_duration = (upload_time - start_time).total_seconds()
    test_duration = (end_time - start_time).total_seconds()

    return {
        "download_duration_s": download_duration,
        "upload_duration_s": upload_duration,
        "packets_duration_s": packets_duration,
        "test_duration_s": test_duration,
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 time-analysis.py <measurement_folder>")
        sys.exit(1)

    measurement_folder = Path(sys.argv[1]).expanduser().resolve()
    csvfile = measurement_folder / "output.csv"

    rows = []
    for file_path in sorted(measurement_folder.rglob("test_output.log")):
        if file_path.is_file():
            result = parse_file(file_path)
            if result is None:
                continue

            rows.append(
                {
                    **result,
                }
            )

    with open(csvfile, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "download_duration_s",
                "upload_duration_s",
                "packets_duration_s",
                "test_duration_s",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {csvfile}")


if __name__ == "__main__":
    main()