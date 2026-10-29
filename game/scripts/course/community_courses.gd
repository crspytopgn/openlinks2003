class_name CommunityCourses
extends RefCounted
## Free fan-made Links 2003 courses that the boot screen suggests. Nothing
## here is bundled: each entry links to the course's Links Corner page, the
## player downloads it there and adds the .zip or .crz to the game. The
## courses are locked like the disc courses, so they open only with the
## player's own copy of the game. Credits: docs/community-courses.md.

## Picked from the fictional, free courses near the top of Links Corner's
## user-rated list (linkscorner.org/courses/index.php?SearchType=Top250).
const COURSES := [
	{"name": "Bull Run HD", "designer": "Eddie Schmidt", "id": 2243},
	{"name": "Pilgrim Trails Golf Club", "designer": "Mike Jones", "id": 1890},
	{"name": "East Coast Links", "designer": "McCoist", "id": 2191},
	{"name": "Duine Mara", "designer": "Paul Seaman", "id": 2022},
	{"name": "Crystal Pines HD", "designer": "Mike Jones", "id": 1974},
]

const PAGE_URL := "https://linkscorner.org/courses/course.php?crz=%d"


static func page_url(course: Dictionary) -> String:
	return PAGE_URL % int(course.id)


## "Duine Mara by Paul Seaman".
static func label(course: Dictionary) -> String:
	return "%s by %s" % [course.name, course.designer]
