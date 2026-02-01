#!/bin/bash
ACTION=$1

CONFIG_DIR="/opt/postgres-ha/config"
TEMPLATE_DIR="/opt/postgres-ha/templates"

case $ACTION in
    "list")
        echo "Configuration Files:"
        echo "==================="
        find "$CONFIG_DIR" -type f -name "*.conf" | sort
        echo ""
        echo "Template Files:"
        echo "==============="
        find "$TEMPLATE_DIR" -type f | sort
        ;;
        
    "show")
        FILE=$2
        if [ -z "$FILE" ]; then
            echo "Usage: $0 show <filename>"
            exit 1
        fi
        
        # Check in config or template directory
        if [ -f "$CONFIG_DIR/$FILE" ]; then
            cat "$CONFIG_DIR/$FILE"
        elif [ -f "$TEMPLATE_DIR/$FILE" ]; then
            cat "$TEMPLATE_DIR/$FILE"
        else
            echo "File not found: $FILE"
            exit 1
        fi
        ;;
        
    "edit")
        FILE=$2
        if [ -z "$FILE" ]; then
            echo "Usage: $0 edit <filename>"
            exit 1
        fi
        
        # Check in config directory first
        if [ -f "$CONFIG_DIR/$FILE" ]; then
            vi "$CONFIG_DIR/$FILE"
        elif [ -f "$TEMPLATE_DIR/$FILE" ]; then
            vi "$TEMPLATE_DIR/$FILE"
        else
            echo "File not found: $FILE"
            exit 1
        fi
        ;;
        
    "sync")
        echo "Syncing configuration to other host..."
        HOST=${2:-host-b}
        rsync -avz "$CONFIG_DIR/" "$HOST:$CONFIG_DIR/" --exclude="*.backup"
        rsync -avz "$TEMPLATE_DIR/" "$HOST:$TEMPLATE_DIR/"
        echo "Configuration synced to $HOST"
        ;;
        
    "backup")
        BACKUP_DIR="/opt/postgres-ha/backup/config-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r "$CONFIG_DIR" "$TEMPLATE_DIR" "$BACKUP_DIR/"
        echo "Backup created: $BACKUP_DIR"
        ;;
        
    *)
        echo "Configuration Management Script"
        echo ""
        echo "Usage: $0 {list|show|edit|sync|backup} [arg]"
        echo ""
        echo "Commands:"
        echo "  list                    List all configuration files"
        echo "  show <file>             Show configuration file content"
        echo "  edit <file>             Edit configuration file"
        echo "  sync [host]             Sync configs to other host"
        echo "  backup                  Backup current configuration"
        ;;
esac
