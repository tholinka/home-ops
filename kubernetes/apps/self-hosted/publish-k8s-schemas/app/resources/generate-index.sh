#!/usr/bin/env bash

cd /config/.datree/crdSchemas/

echo "creating index"

# Count stats
group_count=$(find . -maxdepth 1 -type d | wc -l)
group_count=$((group_count - 1))
schema_count=$(find . -name "*.json" | wc -l)
updated=$(date -u +"%Y-%m-%d")

echo "groups: $group_count - schemas: $schema_count"

# Generate schema cards HTML
schemas_html=""
for dir in */; do
	dir_name="${dir%/}"
	file_count=$(find "$dir" -maxdepth 1 -name "*.json" | wc -l)
	files_html=""
	for file in "$dir"*.json; do
		if [ -f "$file" ]; then
		filename=$(basename "$file")
		files_html="${files_html}<a href=\"${file}\" class=\"file-link\">${filename}</a>"
		fi
	done
	schemas_html="${schemas_html}<div class=\"group-card\"><div class=\"group-header\"><span class=\"group-name\">${dir_name}</span><span class=\"group-count\">${file_count}</span><svg class=\"chevron\" width=\"16\" height=\"16\" viewBox=\"0 0 16 16\" fill=\"currentColor\"><path d=\"M4.427 5.427l3.396 3.396a.25.25 0 00.354 0l3.396-3.396A.25.25 0 0011.396 5H4.604a.25.25 0 00-.177.427z\"/></svg></div><div class=\"group-files\">${files_html}</div></div>"
done

# Copy template and inject data
cp /config/map/index.html index.html
sed -i "s|<!-- SCHEMAS_PLACEHOLDER -->|${schemas_html}|g" index.html
sed -i "s|<div class=\"stat-value\" id=\"group-count\">-</div>|<div class=\"stat-value\" id=\"group-count\">${group_count}</div>|g" index.html
sed -i "s|<div class=\"stat-value\" id=\"schema-count\">-</div>|<div class=\"stat-value\" id=\"schema-count\">${schema_count}</div>|g" index.html
sed -i "s|<div class=\"stat-value\" id=\"last-updated\">-</div>|<div class=\"stat-value\" id=\"last-updated\">${updated}</div>|g" index.html

echo "index created"
