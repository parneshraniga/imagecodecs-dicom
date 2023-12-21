# imagecodecs_dicom/setup.py

"""Imagecodecs package Setuptools script."""

import sys
import os
import re
import shutil

from setuptools import setup, Extension
from setuptools.command.build_ext import build_ext as _build_ext

import numpy
import Cython  # noqa

buildnumber = ''  # e.g 'pre1' or 'post1'

base_dir = os.path.dirname(os.path.abspath(__file__))


def search(pattern, code, flags=0):
    # return first match for pattern in code
    match = re.search(pattern, code, flags)
    if match is None:
        raise ValueError(f'{pattern!r} not found')
    return match.groups()[0]


with open(
    os.path.join(base_dir, 'imagecodecs_dicom/imagecodecs_dicom.py'), encoding='utf-8'
) as fh:
    code = fh.read().replace('\r\n', '\n').replace('\r', '\n')

version = search(r"__version__ = '(.*?)'", code).replace('.x.x', '.dev0')
version += ('.' + buildnumber) if buildnumber else ''

description = search(r'"""(.*)\.(?:\r\n|\r|\n)', code)

readme = search(
    r'(?:\r\n|\r|\n){2}r"""(.*)"""(?:\r\n|\r|\n){2}from __future__',
    code,
    re.MULTILINE | re.DOTALL,
)
readme = '\n'.join(
    [description, '=' * len(description)] + readme.splitlines()[1:]
)

if 'sdist' in sys.argv:
    # update README, LICENSE, and CHANGES files

    with open('README.rst', 'w', encoding='utf-8') as fh:
        fh.write(readme)

    license = search(
        r'(# Copyright.*?(?:\r\n|\r|\n))(?:\r\n|\r|\n)+r""',
        code,
        re.MULTILINE | re.DOTALL,
    )
    license = license.replace('# ', '').replace('#', '')

    with open('LICENSE', 'w', encoding='utf-8') as fh:
        fh.write('BSD 3-Clause License\n\n')
        fh.write(license)

    revisions = search(
        r'(?:\r\n|\r|\n){2}(Revisions.*)- …',
        readme,
        re.MULTILINE | re.DOTALL,
    ).strip()

    with open('CHANGES.rst', encoding='utf-8') as fh:
        old = fh.read()

    old = old.split(revisions.splitlines()[-1])[-1]
    with open('CHANGES.rst', 'w', encoding='utf-8') as fh:
        fh.write(revisions.strip())
        fh.write(old)


def ext(**kwargs):
    """Return Extension arguments."""
    d: dict[str, object] = dict(
        sources=[],
        include_dirs=[],
        library_dirs=[],
        libraries=[],
        define_macros=[],
        extra_compile_args=[],
        extra_link_args=[],
        depends=[],
        cython_compile_time_env={},
    )
    d.update(kwargs)
    return d


OPTIONS = {
    'include_dirs': ['imagecodecs_dicom','/opt/libjpeg-turbo/include/','/home/ran112/Dev/libjpeg-turbo-3.0.1/'],
    'library_dirs': ['/opt/libjpeg-turbo/lib64'],
    'libraries': ['m'] if sys.platform != 'win32' else [],
    'define_macros': [
        # ('CYTHON_TRACE_NOGIL', '1'),
        # ('CYTHON_LIMITED_API', '1'),
        # ('Py_LIMITED_API', '1'),
        # ('NPY_NO_DEPRECATED_API', 'NPY_1_7_API_VERSION')
    ]
    + [('WIN32', 1)]  # type: ignore
    if sys.platform == 'win32'
    else [],
    'extra_compile_args': [],
    'extra_link_args': [],
    # 'extra_compile_args': ['/Zi', '/Od'],
    # 'extra_link_args': ['-debug:full'],
    'depends': ['imagecodecs_dicom/_shared.pxd'],
    'cython_compile_time_env': {},
}

EXTENSIONS = {
    'gif': ext(libraries=['gif']),
    'jpeg2k': ext(
        sources=['3rdparty/openjpeg/color.c'],
        include_dirs=['3rdparty/openjpeg'],
        libraries=['openjp2', 'lcms2'],
    ),
    'jpeg8': ext(
     #   sources=['imagecodecs_dicom/_jpeg8_legacy.pyx'],
        sources=[],
        libraries=['jpeg'],
    ),
#    'jpegls': ext(libraries=['charls']),
    'png': ext(libraries=['png']),
}


def customize_build_default(EXTENSIONS, OPTIONS):
    """Customize build for common platforms: recent Debian, arch..."""
    import platform


    #if 'arch' not in platform.platform():
    #    del EXTENSIONS['jpegls']  # CharLS 2.1 library not commonly available

    if sys.platform == 'win32':
        pass
    else:
        EXTENSIONS['jpeg2k']['include_dirs'].extend(
            (
                '/usr/include/openjpeg-2.3',
                '/usr/include/openjpeg-2.4',
                '/usr/include/openjpeg-2.5',
            )
        )


def customize_build_cgohlke(EXTENSIONS, OPTIONS):
    """Customize build for Windows development environment with static libs."""
    INCLIB = os.environ.get('INCLIB', '.')

    OPTIONS['include_dirs'].append(os.path.join(INCLIB, 'lib'))
    OPTIONS['library_dirs'].append(os.path.join(INCLIB, 'include'))

    dlls: list[str] = []  # 'heif.dll'
    if '64 bit' in sys.version:
        for dll in dlls:
            shutil.copyfile(
                os.path.join(INCLIB, 'bin', dll), 'imagecodecs_dicom/' + dll
            )
    else:
        for dll in dlls:
            try:
                os.remove('imagecodecs_dicom/' + dll)
            except FileNotFoundError:
                pass

    # EXTENSIONS['exr']['define_macros'].append(('TINYEXR_USE_OPENMP', 1))
    # EXTENSIONS['exr']['extra_compile_args'] = ['/openmp']

    if not os.environ.get('USE_JPEG8_LEGACY', False):
        # use libjpeg-turbo 3
        EXTENSIONS['jpeg8']['sources'] = []


    EXTENSIONS['gif']['libraries'] = ['libgif']
    EXTENSIONS['png']['libraries'] = ['png', 'zlibstatic-ng-compat']
    EXTENSIONS['apng']['libraries'] = ['png', 'zlibstatic-ng-compat']


    EXTENSIONS['jpegls']['define_macros'].append(('CHARLS_STATIC', 1))
    EXTENSIONS['jpeg2k']['define_macros'].append(('OPJ_STATIC', 1))
    EXTENSIONS['jpeg2k']['include_dirs'].append(
        os.path.join(INCLIB, 'include', 'openjpeg-2.5')
    )


def customize_build_cibuildwheel(EXTENSIONS, OPTIONS):
    """Customize build for Czaki's cibuildwheel environment."""


    EXTENSIONS['jpeg8']['sources'] = []  # use libjpeg-turbo 3


    OPTIONS['library_dirs'] = [
        x
        for x in os.environ.get(
            'LD_LIBRARY_PATH', os.environ.get('LIBRARY_PATH', '')
        ).split(':')
        if x
    ]

    base_path = os.environ.get(
        'BASE_PATH', os.path.dirname(os.path.abspath(__file__))
    )
    include_base_path = os.path.join(
        base_path, 'build_utils', 'libs_build', 'include'
    )

    OPTIONS['include_dirs'].append(include_base_path)
    for el in os.listdir(include_base_path):
        path_to_dir = os.path.join(include_base_path, el)
        if os.path.isdir(path_to_dir):
            OPTIONS['include_dirs'].append(path_to_dir)

    for dir_path in OPTIONS['include_dirs']:
        if os.path.exists(os.path.join(dir_path, 'jxl', 'types.h')):
            break
    else:
        del EXTENSIONS['jpegxl']


def customize_build_condaforge(EXTENSIONS, OPTIONS):
    """Customize build for conda-forge."""

    del EXTENSIONS['jpegxl']

    # uncomment if building with libjpeg-turbo 3
    EXTENSIONS['jpeg8']['sources'] = []

    if sys.platform == 'win32':

        EXTENSIONS['jpeg2k']['include_dirs'] += [
            os.path.join(
                os.environ['LIBRARY_INC'], 'openjpeg-' + os.environ['openjpeg']
            )
        ]
        EXTENSIONS['jpegls']['libraries'] = ['charls-2-x64']
        EXTENSIONS['png']['libraries'] = ['libpng', 'z']


def customize_build_macports(EXTENSIONS, OPTIONS):
    """Customize build for MacPorts."""

    del EXTENSIONS['jpegls']

    # uncomment if building with libjpeg-turbo 3
    EXTENSIONS['jpeg8']['sources'] = []

    EXTENSIONS['gif']['include_dirs'] = ['%PREFIX%/include/giflib5']
    EXTENSIONS['jpeg2k']['include_dirs'].extend(
        (
            '%PREFIX%/include/openjpeg-2.3',
            '%PREFIX%/include/openjpeg-2.4',
            '%PREFIX%/include/openjpeg-2.5',
        )
    )


def customize_build_mingw(EXTENSIONS, OPTIONS):
    """Customize build for mingw-w64."""


    EXTENSIONS['jpeg8']['sources'] = []  # use libjpeg-turbo 3

    EXTENSIONS['jpeg2k']['include_dirs'].extend(
        (
            sys.prefix + '/include/openjpeg-2.3',
            sys.prefix + '/include/openjpeg-2.4',
            sys.prefix + '/include/openjpeg-2.5',
        )
    )


if 'sdist' not in sys.argv:
    # customize builds based on environment
    try:
        from imagecodecs_distributor_setup import (  # type: ignore
            customize_build,
        )
    except ImportError:
        if os.environ.get('COMPUTERNAME', '').startswith('CG-'):
            customize_build = customize_build_cgohlke
        elif os.environ.get('IMAGECODECS_CIBW', ''):
            customize_build = customize_build_cibuildwheel
        elif os.environ.get('CONDA_BUILD', ''):
            customize_build = customize_build_condaforge
        elif shutil.which('port'):
            customize_build = customize_build_macports
        elif os.name == 'nt' and 'GCC' in sys.version:
            customize_build = customize_build_mingw
        else:
            customize_build = customize_build_default

    customize_build(EXTENSIONS, OPTIONS)


class build_ext(_build_ext):
    """Customize build of extensions.

    Delay importing numpy until building extensions.
    Add numpy include directory to include_dirs.
    Skip building deselected extensions.
    Cythonize with compile time macros.

    """

    user_options = _build_ext.user_options + (
        [('lite', None, 'only build the _imcd extension')]
        + [
            (f'skip-{name}', None, f'do not build the _{name} extension')
            for name in EXTENSIONS
        ]
    )

    def initialize_options(self):
        for name in EXTENSIONS:
            setattr(self, f'skip_{name}', False)
        self.lite = False
        _build_ext.initialize_options(self)

    def finalize_options(self):
        _build_ext.finalize_options(self)

        # remove extensions based on user_options
        for ext in self.extensions.copy():
            name = ext.name.rsplit('_', 1)[-1]
            if (self.lite and name not in {'imcd', 'shared'}) or getattr(
                self, f'skip_{name}', False
            ):
                print(f'skipping {ext.name!r} extension (deselected)')
                self.extensions.remove(ext)

        self.include_dirs.append(numpy.get_include())


def extension(name):
    """Return setuptools Extension."""
    opt = EXTENSIONS[name]
    sources = opt['sources']
    fname = f'imagecodecs_dicom/_{name}'
    if all(not n.startswith(fname) for n in sources):
        sources = [fname + '.pyx'] + sources
    ext = Extension(
        f'imagecodecs_dicom._{name}',
        sources=sources,
        **{
            key: (OPTIONS[key] + opt[key])
            for key in (
                'include_dirs',
                'library_dirs',
                'libraries',
                'define_macros',
                'extra_compile_args',
                'extra_link_args',
                'depends',
            )
        },
    )
    ext.cython_compile_time_env = {
        **OPTIONS['cython_compile_time_env'],  # type: ignore
        **opt['cython_compile_time_env'],
    }
    # ext.force = OPTIONS['cythonize'] or opt['cythonize']
    return ext


setup(
    name='imagecodecs_dicom',
    version=version,
    license='BSD',
    description=description,
    long_description=readme,
    long_description_content_type='text/x-rst',
    author='Christoph Gohlke',
    author_email='cgohlke@cgohlke.com',
    url='https://www.cgohlke.com',
    project_urls={
        'Bug Tracker': 'https://github.com/cgohlke/imagecodecs/issues',
        'Source Code': 'https://github.com/cgohlke/imagecodecs',
        # 'Documentation': 'https://',
    },
    python_requires='>=3.9',
    install_requires=['numpy'],
    # setup_requires=['setuptools', 'numpy', 'cython'],
    extras_require={'all': ['matplotlib', 'tifffile', 'numcodecs']},
    tests_require=[
        'pytest',
        'tifffile',
    ],
    packages=['imagecodecs_dicom'],
    package_data={'imagecodecs_dicom': ['*.pyi', 'py.typed', 'licenses/*']},
    entry_points={
        'console_scripts': ['imagecodecs_dicom=imagecodecs_dicom.__main__:main']
    },
    ext_modules=[extension(name) for name in sorted(EXTENSIONS)],
    cmdclass={'build_ext': build_ext},
    zip_safe=False,
    platforms=['any'],
    classifiers=[
        'Development Status :: 4 - Beta',
        'License :: OSI Approved :: BSD License',
        'Intended Audience :: Science/Research',
        'Intended Audience :: Developers',
        'Operating System :: OS Independent',
        'Programming Language :: C',
        'Programming Language :: Cython',
        'Programming Language :: Python :: 3 :: Only',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'Programming Language :: Python :: 3.12',
        'Programming Language :: Python :: Implementation :: CPython',
    ],
)
