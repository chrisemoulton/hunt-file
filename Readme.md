# 1) Save the script
nano ~/hunt_migration.sh   # paste the script above, save
chmod +x ~/hunt_migration.sh

# 2) Run it (default looks for 'migration.sh' and last 60 days of logs)
sudo ~/hunt_migration.sh

# Optional: hunt a different name and longer log window
sudo TARGET="migration.sh" SINCE="120d" ~/hunt_migration.sh
