import csv
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime
from pathlib import Path

FMT = "%m-%d-%Y %H:%M:%S"

def parse_file(filename: Path):
    experiment = []
    start_time = unloaded_time = download_time = upload_time = end_time = None

    with open(filename, "r", encoding="utf-8") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line:
                continue

            if "UTC Go Responsiveness to" in line:
                parts = line.split()
                start_time = datetime.strptime(f"{parts[0]} {parts[1]}", FMT)

            elif line.startswith("Download phase finished at"):
                download_time = datetime.strptime(line.rsplit("at ", 1)[1].strip(), FMT)

            elif line.startswith("Upload phase finished at"):
                upload_time = datetime.strptime(line.rsplit("at ", 1)[1].strip(), FMT)

            elif "UTC Go Responsiveness Finished" in line:
                parts = line.split()
                end_time = datetime.strptime(f"{parts[0]} {parts[1]}", FMT)

            elif "Unloaded packet generation ended at" in line:
                unloaded_time = datetime.strptime(line.rsplit("at ", 1)[1].strip(), FMT)

            elif "Testing network environment" in line:
                parts = line.split()
                if len(parts) > 3:
                    experiment.append(parts[3])

            elif "Testing test parameter" in line:
                parts = line.split()
                if len(parts) > 4:
                    experiment.extend([parts[3], parts[4]])

    if len(experiment) < 2:
        experiment.append("default")

    if not all([experiment, start_time, unloaded_time, download_time, upload_time, end_time]):
        return None

    return {
        "exp_parameters": " ".join(experiment),
        "unloaded_duration_s": (unloaded_time - start_time).total_seconds(),
        "download_duration_s": (download_time - unloaded_time).total_seconds(),
        "upload_duration_s": (upload_time - download_time).total_seconds(),
        "packets_duration_s": (upload_time - start_time).total_seconds(),
        "test_duration_s": (end_time - start_time).total_seconds(),
    }


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 time-analysis.py <measurement_folder>")
        sys.exit(1)

    measurement_folder = Path(sys.argv[1]).expanduser().resolve()
    files = sorted(measurement_folder.rglob("test_output.log"))

    with ProcessPoolExecutor(max_workers=max(1, os.cpu_count() - 1)) as pool:
        rows = [r for r in pool.map(parse_file, files) if r is not None]

    csvfile = measurement_folder / "time-analysis.csv"
    with open(csvfile, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "exp_parameters",
                "unloaded_duration_s",
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