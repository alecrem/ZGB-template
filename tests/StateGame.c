#include "Banks/SetAutoBank.h"

#include "ZGBMain.h"
#include "Scroll.h"
#include "SpriteManager.h"
#include "TestAssert.h"

IMPORT_MAP(map);

void START() {
	scroll_target = SpriteManagerAdd(SpritePlayer, 50, 50);
	InitScroll(BANK(map), &map, 0, 0);

	TEST_ASSERT(scroll_target != 0, "SpriteManagerAdd returns a valid sprite");
	TEST_ASSERT(scroll_target->x == 50, "sprite x position is set from SpriteManagerAdd's argument");
	TEST_ASSERT(scroll_target->y == 50, "sprite y position is set from SpriteManagerAdd's argument");

	TEST_DONE();
}

void UPDATE() {
}
