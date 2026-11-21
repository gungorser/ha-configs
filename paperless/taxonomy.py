# Applies taxonomy.json (prepended by hook.sh as T) inside the Paperless container through
# `manage.py shell`: creates missing tags and document types, sets tag parents. Additive only.
from documents.models import DocumentType, MatchingModel, Tag

made, moved = [], []
for t in T["tags"]:
    tag, new = Tag.objects.get_or_create(
        name=t["name"], defaults={"matching_algorithm": MatchingModel.MATCH_NONE})
    if new:
        made.append(tag.name)
    parent = Tag.objects.get(name=t["parent"]) if t.get("parent") else None
    if tag.tn_parent_id != (parent.id if parent else None) and (parent or "parent" in t):
        tag.tn_parent = parent
        tag.save()
        moved.append(f"{tag.name}->{parent.name if parent else '-'}")
for name in T["document_types"]:
    _, new = DocumentType.objects.get_or_create(
        name=name, defaults={"matching_algorithm": MatchingModel.MATCH_NONE})
    if new:
        made.append(f"type {name}")
print(f"taxonomy: created {made or 'nothing'}, parents set {moved or 'nothing'}")
