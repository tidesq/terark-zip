export SHELL=bash
DBG_ASAN ?= -fsanitize=address
AFR_ASAN ?= -fsanitize=address
RLS_ASAN ?=

DBG_FLAGS ?= -O0 -D_DEBUG -g3 ${DBG_ASAN}
RLS_FLAGS ?= -O3 -DNDEBUG -g3 ${RLS_ASAN}
# 'AFR' means Assert For Release
AFR_FLAGS ?= -O1 -g3 ${AFR_ASAN}

WITH_BMI2 ?= $(shell bash ./cpu_has_bmi2.sh)
CMAKE_INSTALL_PREFIX ?= /usr

BOOST_INC ?= -Iboost-include

ifeq "$(origin LD)" "default"
  LD := ${CXX}
endif
#ifeq "$(origin CC)" "default"
#  CC := ${CXX}
#endif

# Makefile is stupid to parsing $(shell echo ')')
tmpfile := $(shell mktemp -u compiler-XXXXXX)
COMPILER := $(shell ${CXX} tools/configure/compiler.cpp -o ${tmpfile}.exe && ./${tmpfile}.exe && rm -f ${tmpfile}*)
UNAME_MachineSystem := $(shell uname -m -s | sed 's:[ /]:-:g')
BUILD_NAME := ${UNAME_MachineSystem}-${COMPILER}-bmi2-${WITH_BMI2}
BUILD_ROOT := build/${BUILD_NAME}
ddir:=${BUILD_ROOT}/dbg
rdir:=${BUILD_ROOT}/rls
adir:=${BUILD_ROOT}/afr

TERARK_ROOT:=${PWD}
COMMON_C_FLAGS  += -Wformat=2 -Wcomment
COMMON_C_FLAGS  += -Wall -Wextra
COMMON_C_FLAGS  += -Wno-unused-parameter

gen_sh := $(dir $(lastword ${MAKEFILE_LIST}))gen_env_conf.sh

err := $(shell env BOOST_INC=${BOOST_INC} bash ${gen_sh} "${CXX}" ${COMPILER} ${BUILD_ROOT}/env.mk; echo $$?)
ifneq "${err}" "0"
   $(error err = ${err} MAKEFILE_LIST = ${MAKEFILE_LIST}, PWD = ${PWD}, gen_sh = ${gen_sh} "${CXX}" ${COMPILER} ${BUILD_ROOT}/env.mk)
endif

TERARK_INC := -Isrc -I3rdparty/zstd ${BOOST_INC}

include ${BUILD_ROOT}/env.mk

UNAME_System := $(shell uname | sed 's/^\([0-9a-zA-Z]*\).*/\1/')
ifeq (CYGWIN, ${UNAME_System})
  FPIC =
  # lazy expansion
  CYGWIN_LDFLAGS = -Wl,--out-implib=$@ \
				   -Wl,--export-all-symbols \
				   -Wl,--enable-auto-import
  DLL_SUFFIX = .dll.a
  CYG_DLL_FILE = $(shell echo $@ | sed 's:\(.*\)/lib\([^/]*\)\.a$$:\1/cyg\2:')
  COMMON_C_FLAGS += -D_GNU_SOURCE
else
  ifeq (Darwin,${UNAME_System})
    DLL_SUFFIX = .dylib
  else
    DLL_SUFFIX = .so
  endif
  FPIC = -fPIC
  CYG_DLL_FILE = $@
endif
override CFLAGS += ${FPIC}
override CXXFLAGS += ${FPIC}
override LDFLAGS += ${FPIC}

ASAN_LDFLAGS_a := ${AFR_ASAN}
ASAN_LDFLAGS_d := ${DBG_ASAN}
ASAN_LDFLAGS_r := ${RLS_ASAN}
ASAN_LDFLAGS = ${ASAN_LDFLAGS_$(patsubst %-a,a,$(patsubst %-d,d,$(@:%${DLL_SUFFIX}=%)))}
# ---------- ^-- lazy evaluation, must be '='

CXX_STD := -std=gnu++1y

ifeq "$(shell a=${COMPILER};echo $${a:0:3})" "g++"
  ifeq (Linux, ${UNAME_System})
    override LDFLAGS += -rdynamic
  endif
  ifeq (${UNAME_System},Darwin)
    COMMON_C_FLAGS += -Wa,-q
  endif
  override CXXFLAGS += -time
  ifeq "$(shell echo ${COMPILER} | awk -F- '{if ($$2 >= 9.0) print 1;}')" "1"
    COMMON_C_FLAGS += -Wno-alloc-size-larger-than
  endif
endif

# icc or icpc
ifeq "$(shell a=${COMPILER};echo $${a:0:2})" "ic"
  override CXXFLAGS += -xHost -fasm-blocks
  CPU = -xHost
else
  CPU = -march=haswell
  COMMON_C_FLAGS  += -Wno-deprecated-declarations
  ifeq "$(shell a=${COMPILER};echo $${a:0:5})" "clang"
    COMMON_C_FLAGS  += -fstrict-aliasing
  else
    COMMON_C_FLAGS  += -Wstrict-aliasing=3
  endif
endif

ifeq (${WITH_BMI2},1)
  CPU += -mbmi -mbmi2
else
  CPU += -mno-bmi -mno-bmi2
endif

ifneq (${WITH_TBB},)
  COMMON_C_FLAGS += -DTERARK_WITH_TBB=${WITH_TBB}
  override LIBS += -ltbb
endif

ifeq "$(shell a=${COMPILER};echo $${a:0:5})" "clang"
  COMMON_C_FLAGS += -fcolor-diagnostics
endif

#CXXFLAGS +=
#CXXFLAGS += -fpermissive
#CXXFLAGS += -fexceptions
#CXXFLAGS += -fdump-translation-unit -fdump-class-hierarchy

override CFLAGS += ${COMMON_C_FLAGS}
override CXXFLAGS += ${COMMON_C_FLAGS}
#$(error ${CXXFLAGS} "----" ${COMMON_C_FLAGS})

DEFS := -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE
DEFS += -DDIVSUFSORT_API=
override CFLAGS   += ${DEFS}
override CXXFLAGS += ${DEFS}

override INCS := ${TERARK_INC} ${INCS}

LIBBOOST ?=
#LIBBOOST += -lboost_thread${BOOST_SUFFIX}
#LIBBOOST += -lboost_date_time${BOOST_SUFFIX}
#LIBBOOST += -lboost_system${BOOST_SUFFIX}

#LIBS += -ldl
#LIBS += -lpthread
#LIBS += ${LIBBOOST}

#extf = -pie
extf = -fno-stack-protector
#extf+=-fno-stack-protector-all
override CFLAGS += ${extf}
#override CFLAGS += -g3
override CXXFLAGS += ${extf}
#override CXXFLAGS += -g3
#CXXFLAGS += -fnothrow-opt

ifeq (, ${prefix})
  ifeq (root, ${USER})
    prefix := /usr
  else
    prefix := /home/${USER}
  endif
endif

#$(warning prefix=${prefix} LIBS=${LIBS})

#obsoleted_src =  \
#	$(wildcard src/obsoleted/terark/thread/*.cpp) \
#	$(wildcard src/obsoleted/terark/thread/posix/*.cpp) \
#	$(wildcard src/obsoleted/wordseg/*.cpp)
#LIBS += -liconv

ifneq "$(shell a=${COMPILER};echo $${a:0:5})" "clang"
  override LIBS += -lgomp
endif

c_src := \
   $(wildcard src/terark/c/*.c) \
   $(wildcard src/terark/c/*.cpp)

zip_src := \
    src/terark/io/BzipStream.cpp \
	src/terark/io/GzipStream.cpp

core_src := \
   $(wildcard src/terark/*.cpp) \
   $(wildcard src/terark/io/*.cpp) \
   $(wildcard src/terark/util/*.cpp) \
   $(wildcard src/terark/thread/*.cpp) \
   $(wildcard src/terark/succinct/*.cpp) \
   ${obsoleted_src}

core_src := $(filter-out ${zip_src}, ${core_src})

fsa_src := $(wildcard src/terark/fsa/*.cpp)
fsa_src += $(wildcard src/terark/zsrch/*.cpp)

zbs_src := $(wildcard src/terark/entropy/*.cpp)
zbs_src += $(wildcard src/terark/zbs/*.cpp)

idx_src := $(wildcard src/terark/idx/*.cpp)

zstd_src := $(wildcard 3rdparty/zstd/zstd/common/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/compress/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/decompress/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/deprecated/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/dictBuilder/*.c)
zstd_src += $(wildcard 3rdparty/zstd/zstd/legacy/*.c)

zbs_src += ${zstd_src}

#function definition
#@param:${1} -- targets var prefix, such as core | fsa | zbs | idx
#@param:${2} -- build type: d | r | a
objs = $(addprefix ${${2}dir}/, $(addsuffix .o, $(basename ${${1}_src}))) \
       ${${2}dir}/${${2}dir}/git-version-${1}.o

zstd_d_o := $(call objs,zstd,d)
zstd_r_o := $(call objs,zstd,r)
zstd_a_o := $(call objs,zstd,a)

core_d_o := $(call objs,core,d)
core_r_o := $(call objs,core,r)
core_a_o := $(call objs,core,a)
shared_core_d := ${BUILD_ROOT}/lib_shared/libterark-core-${COMPILER}-d${DLL_SUFFIX}
shared_core_r := ${BUILD_ROOT}/lib_shared/libterark-core-${COMPILER}-r${DLL_SUFFIX}
shared_core_a := ${BUILD_ROOT}/lib_shared/libterark-core-${COMPILER}-a${DLL_SUFFIX}
static_core_d := ${BUILD_ROOT}/lib_static/libterark-core-${COMPILER}-d.a
static_core_r := ${BUILD_ROOT}/lib_static/libterark-core-${COMPILER}-r.a
static_core_a := ${BUILD_ROOT}/lib_static/libterark-core-${COMPILER}-a.a

fsa_d_o := $(call objs,fsa,d)
fsa_r_o := $(call objs,fsa,r)
fsa_a_o := $(call objs,fsa,a)
shared_fsa_d := ${BUILD_ROOT}/lib_shared/libterark-fsa-${COMPILER}-d${DLL_SUFFIX}
shared_fsa_r := ${BUILD_ROOT}/lib_shared/libterark-fsa-${COMPILER}-r${DLL_SUFFIX}
shared_fsa_a := ${BUILD_ROOT}/lib_shared/libterark-fsa-${COMPILER}-a${DLL_SUFFIX}
static_fsa_d := ${BUILD_ROOT}/lib_static/libterark-fsa-${COMPILER}-d.a
static_fsa_r := ${BUILD_ROOT}/lib_static/libterark-fsa-${COMPILER}-r.a
static_fsa_a := ${BUILD_ROOT}/lib_static/libterark-fsa-${COMPILER}-a.a

zbs_d_o := $(call objs,zbs,d)
zbs_r_o := $(call objs,zbs,r)
zbs_a_o := $(call objs,zbs,a)
shared_zbs_d := ${BUILD_ROOT}/lib_shared/libterark-zbs-${COMPILER}-d${DLL_SUFFIX}
shared_zbs_r := ${BUILD_ROOT}/lib_shared/libterark-zbs-${COMPILER}-r${DLL_SUFFIX}
shared_zbs_a := ${BUILD_ROOT}/lib_shared/libterark-zbs-${COMPILER}-a${DLL_SUFFIX}
static_zbs_d := ${BUILD_ROOT}/lib_static/libterark-zbs-${COMPILER}-d.a
static_zbs_r := ${BUILD_ROOT}/lib_static/libterark-zbs-${COMPILER}-r.a
static_zbs_a := ${BUILD_ROOT}/lib_static/libterark-zbs-${COMPILER}-a.a

idx_d_o := $(call objs,idx,d)
idx_r_o := $(call objs,idx,r)
idx_a_o := $(call objs,idx,a)
shared_idx_d := ${BUILD_ROOT}/lib_shared/libterark-idx-${COMPILER}-d${DLL_SUFFIX}
shared_idx_r := ${BUILD_ROOT}/lib_shared/libterark-idx-${COMPILER}-r${DLL_SUFFIX}
shared_idx_a := ${BUILD_ROOT}/lib_shared/libterark-idx-${COMPILER}-a${DLL_SUFFIX}
static_idx_d := ${BUILD_ROOT}/lib_static/libterark-idx-${COMPILER}-d.a
static_idx_r := ${BUILD_ROOT}/lib_static/libterark-idx-${COMPILER}-r.a
static_idx_a := ${BUILD_ROOT}/lib_static/libterark-idx-${COMPILER}-a.a

core := ${shared_core_d} ${shared_core_r} ${shared_core_a} ${static_core_d} ${static_core_r} ${static_core_a}
fsa  := ${shared_fsa_d}  ${shared_fsa_r}  ${shared_fsa_a}  ${static_fsa_d}  ${static_fsa_r}  ${static_fsa_a}
zbs  := ${shared_zbs_d}  ${shared_zbs_r}  ${shared_zbs_a}  ${static_zbs_d}  ${static_zbs_r}  ${static_zbs_a}
idx  := ${shared_idx_d}  ${shared_idx_r}  ${shared_idx_a}  ${static_idx_d}  ${static_idx_r}  ${static_idx_a}

ALL_TARGETS = ${MAYBE_DBB_DBG} ${MAYBE_DBB_RLS} ${MAYBE_DBB_AFR} core fsa zbs idx
DBG_TARGETS = ${MAYBE_DBB_DBG} ${shared_core_d} ${shared_fsa_d} ${shared_zbs_d} ${shared_idx_d}
RLS_TARGETS = ${MAYBE_DBB_RLS} ${shared_core_r} ${shared_fsa_r} ${shared_zbs_r} ${shared_idx_r}
AFR_TARGETS = ${MAYBE_DBB_AFR} ${shared_core_a} ${shared_fsa_a} ${shared_zbs_a} ${shared_idx_a}
ifeq (${PKG_WITH_STATIC},1)
  DBG_TARGETS += ${static_core_d} ${static_fsa_d} ${static_zbs_d} ${static_idx_d}
  RLS_TARGETS += ${static_core_r} ${static_fsa_r} ${static_zbs_r} ${static_idx_r}
  AFR_TARGETS += ${static_core_a} ${static_fsa_a} ${static_zbs_a} ${static_idx_a}
endif


ifeq (${TERARK_BIN_USE_STATIC_LIB},1)
  TERARK_BIN_DEP_LIB := ${static_core_d} ${static_fsa_d} ${static_zbs_d} ${static_idx_d}
else
  TERARK_BIN_DEP_LIB := ${shared_core_d} ${shared_fsa_d} ${shared_zbs_d} ${shared_idx_d}
endif

.PHONY : default all core fsa zbs idx

default : fsa core zbs idx
all : ${ALL_TARGETS}
core: ${core}
fsa: ${fsa}
zbs: ${zbs}
idx: ${idx}

OpenSources := $(shell find -H src 3rdparty -name '*.h' -o -name '*.hpp' -o -name '*.cc' -o -name '*.cpp' -o -name '*.c')

allsrc = ${core_src} ${fsa_src} ${zbs_src} ${idx_src}
alldep = $(addprefix ${rdir}/, $(addsuffix .dep, $(basename ${allsrc}))) \
         $(addprefix ${adir}/, $(addsuffix .dep, $(basename ${allsrc}))) \
         $(addprefix ${ddir}/, $(addsuffix .dep, $(basename ${allsrc})))

.PHONY : dbg rls afr
dbg: ${DBG_TARGETS}
rls: ${RLS_TARGETS}
afr: ${AFR_TARGETS}

ifneq (${UNAME_System},Darwin)
${shared_core_d} ${shared_core_r} ${shared_core_a} : LIBS += -lrt -lpthread -laio
endif
${shared_core_d} : LIBS := $(filter-out -lterark-core-${COMPILER}-d, ${LIBS})
${shared_core_r} : LIBS := $(filter-out -lterark-core-${COMPILER}-r, ${LIBS})
${shared_core_a} : LIBS := $(filter-out -lterark-core-${COMPILER}-a, ${LIBS})

${shared_fsa_d} : LIBS := $(filter-out -lterark-fsa-${COMPILER}-d, -L${BUILD_ROOT}/lib_shared -lterark-core-${COMPILER}-d ${LIBS})
${shared_fsa_r} : LIBS := $(filter-out -lterark-fsa-${COMPILER}-r, -L${BUILD_ROOT}/lib_shared -lterark-core-${COMPILER}-r ${LIBS})
${shared_fsa_a} : LIBS := $(filter-out -lterark-fsa-${COMPILER}-a, -L${BUILD_ROOT}/lib_shared -lterark-core-${COMPILER}-a ${LIBS})

${shared_zbs_d} : LIBS := -L${BUILD_ROOT}/lib_shared -lterark-fsa-${COMPILER}-d -lterark-core-${COMPILER}-d ${LIBS}
${shared_zbs_r} : LIBS := -L${BUILD_ROOT}/lib_shared -lterark-fsa-${COMPILER}-r -lterark-core-${COMPILER}-r ${LIBS}
${shared_zbs_a} : LIBS := -L${BUILD_ROOT}/lib_shared -lterark-fsa-${COMPILER}-a -lterark-core-${COMPILER}-a ${LIBS}

${shared_idx_d} : LIBS := -L${BUILD_ROOT}/lib_shared -lterark-zbs-${COMPILER}-d -lterark-fsa-${COMPILER}-d -lterark-core-${COMPILER}-d ${LIBS}
${shared_idx_r} : LIBS := -L${BUILD_ROOT}/lib_shared -lterark-zbs-${COMPILER}-r -lterark-fsa-${COMPILER}-r -lterark-core-${COMPILER}-r ${LIBS}
${shared_idx_a} : LIBS := -L${BUILD_ROOT}/lib_shared -lterark-zbs-${COMPILER}-a -lterark-fsa-${COMPILER}-a -lterark-core-${COMPILER}-a ${LIBS}

${zstd_d_o} ${zstd_r_o} ${zstd_a_o} : override CFLAGS += -Wno-sign-compare -Wno-implicit-fallthrough

${shared_fsa_d} : $(call objs,fsa,d) ${shared_core_d}
${shared_fsa_r} : $(call objs,fsa,r) ${shared_core_r}
${shared_fsa_a} : $(call objs,fsa,a) ${shared_core_a}
${static_fsa_d} : $(call objs,fsa,d)
${static_fsa_r} : $(call objs,fsa,r)
${static_fsa_a} : $(call objs,fsa,a)

${shared_zbs_d} : $(call objs,zbs,d) ${shared_fsa_d} ${shared_core_d}
${shared_zbs_r} : $(call objs,zbs,r) ${shared_fsa_r} ${shared_core_r}
${shared_zbs_a} : $(call objs,zbs,a) ${shared_fsa_a} ${shared_core_a}
${static_zbs_d} : $(call objs,zbs,d)
${static_zbs_r} : $(call objs,zbs,r)
${static_zbs_a} : $(call objs,zbs,a)

${shared_idx_d} : $(call objs,idx,d) ${shared_zbs_d} ${shared_fsa_d} ${shared_core_d}
${shared_idx_r} : $(call objs,idx,r) ${shared_zbs_r} ${shared_fsa_r} ${shared_core_r}
${shared_idx_a} : $(call objs,idx,a) ${shared_zbs_a} ${shared_fsa_a} ${shared_core_a}
${static_idx_d} : $(call objs,idx,d)
${static_idx_r} : $(call objs,idx,r)
${static_idx_a} : $(call objs,idx,a)

${shared_core_d}:${core_d_o} 3rdparty/base64/lib/libbase64.o boost-include/build-lib-for-terark.done
${shared_core_r}:${core_r_o} 3rdparty/base64/lib/libbase64.o boost-include/build-lib-for-terark.done
${shared_core_a}:${core_a_o} 3rdparty/base64/lib/libbase64.o boost-include/build-lib-for-terark.done
${static_core_d}:${core_d_o} 3rdparty/base64/lib/libbase64.o boost-include/build-lib-for-terark.done
${static_core_r}:${core_r_o} 3rdparty/base64/lib/libbase64.o boost-include/build-lib-for-terark.done
${static_core_a}:${core_a_o} 3rdparty/base64/lib/libbase64.o boost-include/build-lib-for-terark.done

${static_core_d} ${shared_core_d}: BOOST_VARIANT := debug
${static_core_r} ${shared_core_r}: BOOST_VARIANT := release
${static_core_a} ${shared_core_a}: BOOST_VARIANT := release

#@param ${1}: release|debug
define BOOST_OBJS
  $(shell \
  if test -n "${1}"; then  \
    if test "$(suffix $@)" = ".a"; \
    then \
      DirSig=${1}/link-static/threading-multi; \
    else \
      DirSig=${1}/threading-multi; \
    fi; \
    find boost-include/bin.v2/libs \
        -path "*/$$DirSig/*" -name '*.o' \
        -not -path "boost-include/bin.v2/libs/config/*"; \
  fi)
endef

# must use '=' for lazy evaluation, do not use ':='
THIS_LIB_OBJS = $(sort $(filter %.o,$^) $(call BOOST_OBJS,${BOOST_VARIANT}))

define GenGitVersionSRC
${1}/git-version-core.cpp: ${core_src}
${1}/git-version-fsa.cpp: ${fsa_src}
${1}/git-version-zbs.cpp: ${zbs_src}
${1}/git-version-%.cpp: Makefile
	@mkdir -p $$(dir $$@)
	@rm -f $$@.tmp
	@echo '__attribute__ ((visibility ("default"))) const char*' \
		  'git_version_hash_info_'$$(patsubst git-version-%.cpp,%,$$(notdir $$@))\
		  '() { return R"StrLiteral(git_version_hash_info_is:' > $$@.tmp
	@env LC_ALL=C git log -n1 >> $$@.tmp
	@env LC_ALL=C git diff >> $$@.tmp
	@env LC_ALL=C $(CXX) --version >> $$@.tmp
	@echo INCS = ${INCS}           >> $$@.tmp
	@echo CXXFLAGS  = ${CXXFLAGS}  >> $$@.tmp
	@echo ${2} >> $$@.tmp # DBG_FLAGS | RLS_FLAGS | AFR_FLAGS
	@echo WITH_BMI2 = ${WITH_BMI2} >> $$@.tmp
	@echo WITH_TBB  = ${WITH_TBB}  >> $$@.tmp
	@echo compile_cpu_flag: $(CPU) >> $$@.tmp
	@#echo machine_cpu_flag: Begin  >> $$@.tmp
	@#bash ./cpu_features.sh        >> $$@.tmp
	@#echo machine_cpu_flag: End    >> $$@.tmp
	@echo ')''StrLiteral";}' >> $$@.tmp
	@#      ^^----- To prevent diff causing git-version compile fail
	@if test -f "$$@" && cmp "$$@" $$@.tmp; then \
		rm $$@.tmp; \
	else \
		mv $$@.tmp $$@; \
	fi
endef

$(eval $(call GenGitVersionSRC, ${ddir}, "DBG_FLAGS = ${DBG_FLAGS}"))
$(eval $(call GenGitVersionSRC, ${rdir}, "RLS_FLAGS = ${RLS_FLAGS}"))
$(eval $(call GenGitVersionSRC, ${adir}, "AFR_FLAGS = ${AFR_FLAGS}"))

3rdparty/base64/lib/libbase64.o:
	$(MAKE) -C 3rdparty/base64 clean; \
	$(MAKE) -C 3rdparty/base64 lib/libbase64.o \
		CFLAGS="-fPIC -std=c99 -O3 -Wall -Wextra -pedantic"
		#AVX2_CFLAGS=-mavx2 SSE41_CFLAGS=-msse4.1 SSE42_CFLAGS=-msse4.2 AVX_CFLAGS=-mavx

boost-include/build-lib-for-terark.done:
	cd boost-include \
		&& bash bootstrap.sh --with-libraries=fiber,context,system,filesystem \
		&& ./b2 -j8 cxxflags="-fPIC -std=gnu++14" cflags=-fPIC link=static threading=multi variant=debug \
		&& ./b2 -j8 cxxflags="-fPIC -std=gnu++14" cflags=-fPIC link=static threading=multi variant=release \
		&& ./b2 -j8 cxxflags="-fPIC -std=gnu++14" cflags=-fPIC link=shared threading=multi variant=debug \
		&& ./b2 -j8 cxxflags="-fPIC -std=gnu++14" cflags=-fPIC link=shared threading=multi variant=release
	touch $@

%${DLL_SUFFIX}:
	@echo "----------------------------------------------------------------------------------"
	@echo "Creating shared library: $@"
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	@echo -e "OBJS:" $(addprefix "\n  ",${THIS_LIB_OBJS})
	@echo -e "LIBS:" $(addprefix "\n  ",${LIBS})
	@mkdir -p ${BUILD_ROOT}/lib_shared
ifeq (Darwin, ${UNAME_System})
	@cd ${BUILD_ROOT}; ln -sfh lib_shared lib
else
	@cd ${BUILD_ROOT}; ln -sfT lib_shared lib
endif
	@rm -f $@
	@echo ASAN_LDFLAGS = ${ASAN_LDFLAGS}
	${LD} -shared ${THIS_LIB_OBJS} ${ASAN_LDFLAGS} ${LDFLAGS} ${LIBS} -o ${CYG_DLL_FILE} ${CYGWIN_LDFLAGS}
	cd $(dir $@); ln -sf $(notdir $@) $(subst -${COMPILER},,$(notdir $@))
ifeq (CYGWIN, ${UNAME_System})
	@cp -l -f ${CYG_DLL_FILE} /usr/bin
endif

%.a:
	@echo "----------------------------------------------------------------------------------"
	@echo "Creating static library: $@"
	@echo BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	@echo -e "OBJS:" $(addprefix "\n  ",${THIS_LIB_OBJS})
	@echo -e "LIBS:" $(addprefix "\n  ",${LIBS})
	@mkdir -p $(dir $@)
	@rm -f $@
	${AR} rcs $@ ${THIS_LIB_OBJS};
	cd $(dir $@); ln -sf $(notdir $@) $(subst -${COMPILER},,$(notdir $@))

.PHONY : install
install : core
	cp ${BUILD_ROOT}/lib_shared/* ${prefix}/lib/

.PHONY : clean
clean:
	rm -rf boost-include/bin.v2 boost-include/build-lib-for-terark.done
	@for f in `find * -name "*${BUILD_NAME}*"`; do \
		echo rm -rf $${f}; \
		rm -rf $${f}; \
	done

.PHONY : cleanall
cleanall:
	rm -rf boost-include/bin.v2 boost-include/build-lib-for-terark.done
	@for f in `find build tools tests gtests -name build`; do \
		echo rm -rf $${f}; \
		rm -rf $${f}; \
	done
	rm -rf pkg

.PHONY : depends
depends : ${alldep}

TarBallBaseName := terark-fsa_all-${BUILD_NAME}
TarBall := pkg/${TarBallBaseName}
.PHONY : pkg
.PHONY : tgz
pkg : ${TarBall}
tgz : ${TarBall}.tgz

${TarBall}: $(wildcard tools/general/*.cpp) \
			$(wildcard tools/fsa/*.cpp) \
			$(wildcard tools/zbs/*.cpp) \
			${core} ${fsa} ${zbs} ${idx}
	+${MAKE} CHECK_TERARK_FSA_LIB_UPDATE=0 -C tools/fsa
	+${MAKE} CHECK_TERARK_FSA_LIB_UPDATE=0 -C tools/zbs
	+${MAKE} CHECK_TERARK_FSA_LIB_UPDATE=0 -C tools/general
	rm -rf ${TarBall}
	mkdir -p ${TarBall}/bin
	mkdir -p ${TarBall}/lib_shared
	cd ${TarBall};ln -s lib_shared lib
	mkdir -p ${TarBall}/include/terark/entropy
	mkdir -p ${TarBall}/include/terark/idx
	mkdir -p ${TarBall}/include/terark/thread
	mkdir -p ${TarBall}/include/terark/succinct
	mkdir -p ${TarBall}/include/terark/io/win
	mkdir -p ${TarBall}/include/terark/util
	mkdir -p ${TarBall}/include/terark/fsa
	mkdir -p ${TarBall}/include/terark/fsa/ppi
	mkdir -p ${TarBall}/include/terark/zbs
	mkdir -p ${TarBall}/include/zstd/common
	cp    src/terark/bits_rotate.hpp             ${TarBall}/include/terark
	cp    src/terark/bitfield_array.hpp          ${TarBall}/include/terark
	cp    src/terark/bitfield_array_access.hpp   ${TarBall}/include/terark
	cp    src/terark/bitmanip.hpp                ${TarBall}/include/terark
	cp    src/terark/bitmap.hpp                  ${TarBall}/include/terark
	cp    src/terark/config.hpp                  ${TarBall}/include/terark
	cp    src/terark/cxx_features.hpp            ${TarBall}/include/terark
	cp    src/terark/fstring.hpp                 ${TarBall}/include/terark
	cp    src/terark/histogram.hpp               ${TarBall}/include/terark
	cp    src/terark/int_vector.hpp              ${TarBall}/include/terark
	cp    src/terark/lcast.hpp                   ${TarBall}/include/terark
	cp    src/terark/*hash*.hpp                  ${TarBall}/include/terark
	cp    src/terark/heap_ext.hpp                ${TarBall}/include/terark
	cp    src/terark/mempool*.hpp                ${TarBall}/include/terark
	cp    src/terark/node_layout.hpp             ${TarBall}/include/terark
	cp    src/terark/num_to_str.hpp              ${TarBall}/include/terark
	cp    src/terark/parallel_lib.hpp            ${TarBall}/include/terark
	cp    src/terark/pass_by_value.hpp           ${TarBall}/include/terark
	cp    src/terark/rank_select.hpp             ${TarBall}/include/terark
	cp    src/terark/stdtypes.hpp                ${TarBall}/include/terark
	cp    src/terark/valvec.hpp                  ${TarBall}/include/terark
	cp    src/terark/entropy/*.hpp               ${TarBall}/include/terark/entropy
	cp    src/terark/idx/*.hpp                   ${TarBall}/include/terark/idx
	cp    src/terark/io/*.hpp                    ${TarBall}/include/terark/io
	cp    src/terark/io/win/*.hpp                ${TarBall}/include/terark/io/win
	cp    src/terark/util/*.hpp                  ${TarBall}/include/terark/util
	cp    src/terark/fsa/*.hpp                   ${TarBall}/include/terark/fsa
	cp    src/terark/fsa/*.inl                   ${TarBall}/include/terark/fsa
	cp    src/terark/fsa/ppi/*.hpp               ${TarBall}/include/terark/fsa/ppi
	cp    src/terark/zbs/*.hpp                   ${TarBall}/include/terark/zbs
	cp    src/terark/thread/*.hpp                ${TarBall}/include/terark/thread
	cp    src/terark/succinct/*.hpp              ${TarBall}/include/terark/succinct
	cp    3rdparty/zstd/zstd/*.h                 ${TarBall}/include/zstd
	cp    3rdparty/zstd/zstd/common/*.h          ${TarBall}/include/zstd/common
ifeq (${PKG_WITH_DBG},1)
	cp -a ${BUILD_ROOT}/lib_shared/libterark-{idx,fsa,zbs,core}-*d${DLL_SUFFIX} ${TarBall}/lib_shared
	cp -a ${BUILD_ROOT}/lib_shared/libterark-{idx,fsa,zbs,core}-*a${DLL_SUFFIX} ${TarBall}/lib_shared
  ifeq (${PKG_WITH_STATIC},1)
	mkdir -p ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib_static/libterark-{idx,fsa,zbs,core}-{${COMPILER}-,}d.a ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib_static/libterark-{idx,fsa,zbs,core}-{${COMPILER}-,}a.a ${TarBall}/lib_static
  endif
endif
	cp -a ${BUILD_ROOT}/lib_shared/libterark-{idx,fsa,zbs,core}-*r${DLL_SUFFIX} ${TarBall}/lib_shared
	echo $(shell date "+%Y-%m-%d %H:%M:%S") > ${TarBall}/package.buildtime.txt
	echo $(shell git log | head -n1) >> ${TarBall}/package.buildtime.txt
ifeq (${PKG_WITH_STATIC},1)
	mkdir -p ${TarBall}/lib_static
	cp -a ${BUILD_ROOT}/lib_static/libterark-{idx,fsa,zbs,core}-{${COMPILER}-,}r.a ${TarBall}/lib_static
endif
	cp -L tools/*/rls/*.exe ${TarBall}/bin/

${TarBall}.tgz: ${TarBall}
	cd pkg; tar czf ${TarBallBaseName}.tgz ${TarBallBaseName}

.PONY: test
.PONY: test_dbg
.PONY: test_afr
.PONY: test_rls
test: test_dbg test_afr test_rls

test_dbg: ${TERARK_BIN_DEP_LIB}
	+$(MAKE) -C tests/core        test_dbg  CHECK_TERARK_FSA_LIB_UPDATE=0
	+$(MAKE) -C tests/tries       test_dbg  CHECK_TERARK_FSA_LIB_UPDATE=0
	+$(MAKE) -C tests/succinct    test_dbg  CHECK_TERARK_FSA_LIB_UPDATE=0

test_afr: ${TERARK_BIN_DEP_LIB}
	+$(MAKE) -C tests/core        test_afr  CHECK_TERARK_FSA_LIB_UPDATE=0
	+$(MAKE) -C tests/tries       test_afr  CHECK_TERARK_FSA_LIB_UPDATE=0
	+$(MAKE) -C tests/succinct    test_afr  CHECK_TERARK_FSA_LIB_UPDATE=0

test_rls: ${TERARK_BIN_DEP_LIB}
	+$(MAKE) -C tests/core        test_rls  CHECK_TERARK_FSA_LIB_UPDATE=0
	+$(MAKE) -C tests/tries       test_rls  CHECK_TERARK_FSA_LIB_UPDATE=0
	+$(MAKE) -C tests/succinct    test_rls  CHECK_TERARK_FSA_LIB_UPDATE=0

ifneq ($(MAKECMDGOALS),cleanall)
ifneq ($(MAKECMDGOALS),clean)
-include ${alldep}
endif
endif

#@param ${1} file name suffix: cpp | cxx | cc
#@PARAM ${2} build dir       : ddir | rdir | adir
#@param ${3} debug flag      : DBG_FLAGS | RLS_FLAGS | AFR_FLAGS
define COMPILE_CXX
${2}/%.o: %.${1}
	@echo file: $$< "->" $$@
	@echo TERARK_INC=${TERARK_INC} BOOST_INC=${BOOST_INC} BOOST_SUFFIX=${BOOST_SUFFIX}
	@mkdir -p $$(dir $$@)
	${CXX} ${CXX_STD} ${CPU} -c ${3} ${CXXFLAGS} ${INCS} $$< -o $$@
${2}/%.s : %.${1}
	@echo file: $$< "->" $$@
	${CXX} -S -fverbose-asm ${CXX_STD} ${CPU} ${3} ${CXXFLAGS} ${INCS} $$< -o $$@
${2}/%.dep : %.${1}
	@echo file: $$< "->" $$@
	@echo INCS = ${INCS}
	mkdir -p $$(dir $$@)
	-${CXX} ${CXX_STD} ${3} -M -MT $$(basename $$@).o ${INCS} $$< > $$@
endef

define COMPILE_C
${2}/%.o : %.${1}
	@echo file: $$< "->" $$@
	mkdir -p $$(dir $$@)
	${CC} -c ${CPU} ${3} ${CFLAGS} ${INCS} $$< -o $$@
${2}/%.s : %.${1}
	@echo file: $$< "->" $$@
	${CC} -S -fverbose-asm ${CPU} ${3} ${CFLAGS} ${INCS} $$< -o $$@
${2}/%.dep : %.${1}
	@echo file: $$< "->" $$@
	@echo INCS = ${INCS}
	mkdir -p $$(dir $$@)
	-${CC} ${3} -M -MT $$(basename $$@).o ${INCS} $$< > $$@
endef

$(eval $(call COMPILE_CXX,cpp,${ddir},${DBG_FLAGS}))
$(eval $(call COMPILE_CXX,cxx,${ddir},${DBG_FLAGS}))
$(eval $(call COMPILE_CXX,cc ,${ddir},${DBG_FLAGS}))
$(eval $(call COMPILE_CXX,cpp,${rdir},${RLS_FLAGS}))
$(eval $(call COMPILE_CXX,cxx,${rdir},${RLS_FLAGS}))
$(eval $(call COMPILE_CXX,cc ,${rdir},${RLS_FLAGS}))
$(eval $(call COMPILE_CXX,cpp,${adir},${AFR_FLAGS}))
$(eval $(call COMPILE_CXX,cxx,${adir},${AFR_FLAGS}))
$(eval $(call COMPILE_CXX,cc ,${adir},${AFR_FLAGS}))
$(eval $(call COMPILE_C  ,c  ,${ddir},${DBG_FLAGS}))
$(eval $(call COMPILE_C  ,c  ,${rdir},${RLS_FLAGS}))
$(eval $(call COMPILE_C  ,c  ,${adir},${AFR_FLAGS}))

# disable buildin suffix-rules
.SUFFIXES:
