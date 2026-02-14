#ifndef TEEK_MGBA_H
#define TEEK_MGBA_H

#include <ruby.h>
#include <mgba/core/core.h>
#include <mgba/core/config.h>
#include <mgba/core/directories.h>
#include <mgba/core/log.h>
#include <mgba-util/vfs.h>

extern VALUE mTeek;
extern VALUE mTeekMGBA;

void Init_teek_mgba(void);

#endif /* TEEK_MGBA_H */
