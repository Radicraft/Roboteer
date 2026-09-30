class_name CrowdPeopleData extends Resource
## The 3D crowd's baked people (docs/wave-c-crowd-notes.md): one mesh per MakeHuman person
## at two detail levels, all animated from one vertex animation texture
## (crowd/crowd_people_vat.png). Written by qa/_crowd_people_bake.gd from the Blender
## exporter's JSON (Tools/blender/arena_kit/crowd_vat_human.py); the game only loads it.
##
## Mesh vertex data: COLOR = baked albedo (sRGB), UV = (VAT column, person's first VAT row),
## UV2.x = zone (0 skin, 1 top, 2 bottom, 3 hat, 4 hair, 5 shoes, 6 scarf, 7 phone).

@export var names: PackedStringArray = PackedStringArray()
@export var heights: PackedFloat32Array = PackedFloat32Array()
@export var meshes: Array[ArrayMesh] = []
@export var far_meshes: Array[ArrayMesh] = []
## Clip table: name -> Vector3(first frame, frame count, seconds per frame).
@export var clips: Dictionary = {}
@export var frames := 0
@export var pos_min := Vector3(-0.95, -0.6, -0.95)
@export var pos_max := Vector3(0.95, 2.45, 0.95)
