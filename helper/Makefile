# Makefile template for shared library

CPP        = g++
CXXFLAGS   = -fPIC -Wall -Wextra -O3 -g `pkg-config vips-cpp --cflags`
LDFLAGS    = -shared `pkg-config vips-cpp --libs`
RM         = rm -f
TARGET_LIB = libAssetryHelper.so

SRCS = assetry.cc # source files
OBJS = $(SRCS:.cc=.o)

.PHONY: all
all: ${TARGET_LIB}

$(TARGET_LIB): $(OBJS)
	$(CPP) -o $@ $^ ${LDFLAGS}

$(SRCS:.cc=.d):%.d:%.cc
	$(CPP) $(CXXFLAGS) -MM $< >$@

include $(SRCS:.cc=.d)

install: all
	cp *.so /usr/local/lib

clean:
	-${RM} ${TARGET_LIB} ${OBJS} $(SRCS:.cc=.d)

dylib: ${TARGET_LIB}
	$(CPP) -dynamiclib *.o -o libAssetryHelper.dylib ${LDFLAGS}
	cp libAssetryHelper.dylib /opt/homebrew/lib/libAssetryHelper.dylib
