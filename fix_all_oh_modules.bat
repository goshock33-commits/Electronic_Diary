@echo off
cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\entry"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul
if exist oh_modules\@ohos\shared (echo FIXED entry) else (echo FAILED entry)

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\checkin"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\todo"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\diary"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\gesture-diary"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\pomodoro"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\quote"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\search"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\statistics"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\voice-memo"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

cd /d "D:\Electronic-Diary-huawei\Electronic_Diary\features\weather"
mkdir oh_modules\@ohos 2>nul
move oh_modules\shared oh_modules\@ohos\shared 2>nul

echo ALL DONE
