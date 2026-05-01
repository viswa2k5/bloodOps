files = [
    "backend/admin_function.py",
    "backend/certificate_function.py",
    "backend/donor_function.py",
    "backend/history_function.py",
    "backend/match_function.py",
    "backend/reminder_function.py",
    "backend/request_function.py",
    "frontend/admin-secret-bloodops-2026.html",
    "frontend/admin.html",
    "frontend/index.html",
    "frontend/style.css",
    ".github/workflows/deploy.yml",
    "terraform/main.tf",
    ".gitignore",
    "README.md",
    "LICENSE"
]

with open("ALL_CODE.txt", "w", encoding="utf-8") as out:
    for path in files:
        out.write("\n\n==================== " + path + " ====================\n\n")
        try:
            with open(path, "r", encoding="utf-8") as f:
                out.write(f.read())
        except Exception as e:
            out.write("ERROR reading " + path + ": " + str(e) + "\n")