#!/bin/bash
echo "🧹 ClickHouse Cleanup"
echo "====================="

read -p "⚠️  This will remove ALL data and logs. Are you sure? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🛑 Stopping containers..."
    docker-compose down
    
    echo "🗑️  Removing data and logs..."
    sudo rm -rf data/* logs/*
    
    echo "🐳 Removing Docker volumes..."
    docker-compose down -v
    
    echo "✅ Cleanup completed!"
else
    echo "❌ Cleanup cancelled"
fi
