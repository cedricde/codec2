/*---------------------------------------------------------------------------*\
                                                                             
  FILE........: dump.h
  AUTHOR......: David Rowe                                                          
  DATE CREATED: 25/8/09                                                       
                                                                             
  Routines to dump data to text files for Octave analysis.

\*---------------------------------------------------------------------------*/

/*
  All rights reserved.

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2, as
  published by the Free Software Foundation.  This program is
  distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
  License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/

#ifndef __DUMP__
#define __DUMP__

#include "sine.h"

void dump_on(char filename_prefix[]);
void dump_off();
void dump_Sn(float Sn[]);
void dump_Sw(COMP Sw[]);
void dump_Sw_(COMP Sw_[]);
void dump_model(MODEL *m);
void dump_quantised_model(MODEL *m);
void dump_Pw(COMP Pw[]);
void dump_lsp(float lsp[]);

#endif
