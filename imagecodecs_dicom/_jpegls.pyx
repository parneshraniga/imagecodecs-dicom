# imagecodecs_dicom/_jpegls.pyx
# distutils: language = c
# cython: language_level = 3
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
# cython: nonecheck=False

# Copyright (c) 2019-2023, Christoph Gohlke
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

"""JPEG LS codec for the imagecodecs package."""

__version__ = '2023.7.4'

include '_shared.pxi'

from charls cimport *

from dcm_meta import DCMPixelMeta


class JPEGLS:
    """JPEGLS codec constants."""

    available = True


class JpeglsError(RuntimeError):
    """JPEGLS codec exceptions."""

    def __init__(self, func, err):
        cdef:
            char* error_message
            charls_jpegls_errc error_value

        try:
            error_value = int(err)
            error_message = <char*> charls_get_error_message(error_value)
            msg = error_message.decode().strip()
        except Exception:
            msg = 'NULL' if err is None else f'unknown error {err!r}'
        msg = f'{func} returned {msg}'
        super().__init__(msg)


def jpegls_version():
    """Return CharLS library version string."""
    return 'charls {}.{}.{}'.format(
        CHARLS_VERSION_MAJOR, CHARLS_VERSION_MINOR, CHARLS_VERSION_PATCH
    )


def jpegls_check(data):
    """Return whether data is JPEGLS encoded image."""


def jpegls_encode(data, level=None, out=None):
    """Return JPEGLS encoded image."""
    cdef:
        numpy.ndarray src = numpy.ascontiguousarray(data)
        const uint8_t[::1] dst  # must be const to write to bytes
        ssize_t dstsize
        ssize_t srcsize = src.nbytes
        charls_jpegls_errc ret
        charls_jpegls_encoder* encoder = NULL
        charls_frame_info frameinfo
        # charls_jpegls_pc_parameters preset_coding_parameters
        charls_interleave_mode interleave_mode
        int32_t near_lossless = _default_value(level, 0, 0, 9)
        uint32_t rowstride = <uint32_t> src.strides[0]
        size_t byteswritten
        size_t size_in_bytes

    if not (
        src.dtype in {numpy.uint8, numpy.uint16}
        and src.ndim in {2, 3}
        and srcsize < 4294967296U
    ):
        raise ValueError('invalid data shape or dtype')

    out, dstsize, outgiven, outtype = _parse_output(out)

    if out is not None:
        dst = out
        dstsize = dst.nbytes
    elif dstsize > 0:
        out = _create_output(outtype, dstsize)
        dst = out
        dstsize = dst.nbytes

    # memset(&preset_coding_parameters, 0, sizeof(charls_jpegls_pc_parameters))
    # preset_coding_parameters.maximum_sample_value = 0
    # preset_coding_parameters.threshold1 = 0
    # preset_coding_parameters.threshold2 = 0
    # preset_coding_parameters.threshold3 = 0
    # preset_coding_parameters.reset_value = 0

    # memset(&frameinfo, 0, sizeof(charls_frame_info))
    frameinfo.width = <uint32_t> src.shape[1]
    frameinfo.height = <uint32_t> src.shape[0]
    frameinfo.bits_per_sample = <int32_t> (src.itemsize * 8)

    if src.ndim == 2 or src.shape[2] == 1:
        frameinfo.component_count = 1
        interleave_mode = CHARLS_INTERLEAVE_MODE_NONE
    elif src.shape[2] == 3:
        frameinfo.component_count = 3
        interleave_mode = CHARLS_INTERLEAVE_MODE_SAMPLE
    elif src.shape[2] == 4:
        frameinfo.component_count = 4
        interleave_mode = CHARLS_INTERLEAVE_MODE_LINE
    else:
        raise ValueError('invalid shape')

    try:
        with nogil:
            encoder = charls_jpegls_encoder_create()
            if encoder == NULL:
                raise JpeglsError('charls_jpegls_encoder_create', None)

            ret = charls_jpegls_encoder_set_frame_info(encoder, &frameinfo)
            if ret:
                raise JpeglsError('charls_jpegls_encoder_set_frame_info', ret)

            ret = charls_jpegls_encoder_set_near_lossless(
                encoder,
                near_lossless
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_encoder_set_near_lossless', ret
                )

            ret = charls_jpegls_encoder_set_interleave_mode(
                encoder,
                interleave_mode
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_encoder_set_interleave_mode', ret
                )

            # ret = charls_jpegls_encoder_set_color_transformation(
            #     encoder,
            #     color_transformation
            # )
            # if ret:
            #     raise JpeglsError(
            #         'charls_jpegls_encoder_set_color_transformation', ret
            #     )

            # ret charls_jpegls_encoder_set_preset_coding_parameters(
            #     encoder,
            #     &preset_coding_parameters
            # )
            # if ret:
            #     raise JpeglsError(
            #         'charls_jpegls_encoder_set_preset_coding_parameters', ret
            #     )

            if dstsize < 0:
                ret = charls_jpegls_encoder_get_estimated_destination_size(
                    encoder,
                    &size_in_bytes
                )
                if ret:
                    raise JpeglsError(
                        'charls_jpegls_encoder_get_estimated_destination_size',
                        ret
                    )
                dstsize = size_in_bytes + sizeof(charls_spiff_header)
                with gil:
                    out = _create_output(outtype, dstsize)
                    dst = out
                    dstsize = dst.nbytes

            ret = charls_jpegls_encoder_set_destination_buffer(
                encoder,
                <void*> &dst[0],
                <size_t> dstsize
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_encoder_set_destination_buffer', ret
                )

            ret = charls_jpegls_encoder_write_standard_spiff_header(
                encoder,
                CHARLS_SPIFF_COLOR_SPACE_RGB,
                CHARLS_SPIFF_RESOLUTION_UNITS_DOTS_PER_INCH,
                300,
                300
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_encoder_write_standard_spiff_header', ret
                )

            ret = charls_jpegls_encoder_encode_from_buffer(
                encoder,
                <const void*> src.data,
                <size_t> srcsize,
                <uint32_t> rowstride
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_encoder_encode_from_buffer', ret
                )

            ret = charls_jpegls_encoder_get_bytes_written(
                encoder,
                &byteswritten
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_encoder_get_bytes_written', ret
                )
    finally:
        if encoder != NULL:
            charls_jpegls_encoder_destroy(encoder)

    del dst


    return _return_output(out, dstsize, byteswritten, outgiven)


def jpegls_decode(data, out=None):
    """Return decoded JPEGLS image."""
    cdef:
        numpy.ndarray dst
        const uint8_t[::1] src = data
        ssize_t srcsize = src.size
        ssize_t dstsize
        ssize_t itemsize = 0
        charls_jpegls_errc ret
        charls_jpegls_decoder* decoder = NULL
        charls_interleave_mode interleave_mode
        charls_frame_info frameinfo
        # charls_spiff_header spiff_header
        # int32_t header_found

    if data is out:
        raise ValueError('cannot decode in-place')

    try:
        with nogil:
            decoder = charls_jpegls_decoder_create()
            if decoder == NULL:
                raise JpeglsError('charls_jpegls_decoder_create', None)

            ret = charls_jpegls_decoder_set_source_buffer(
                decoder,
                <void*> &src[0],
                <size_t> srcsize
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_decoder_set_source_buffer', ret
                )

            # ret = charls_jpegls_decoder_read_spiff_header(
            #     decoder,
            #     &spiff_header,
            #     &header_found
            # )
            # if ret:
            #     raise JpeglsError(
            #         'charls_jpegls_decoder_read_spiff_header', ret
            #     )

            ret = charls_jpegls_decoder_read_header(decoder)
            if ret:
                raise JpeglsError('charls_jpegls_decoder_read_header', ret)

            ret = charls_jpegls_decoder_get_frame_info(decoder, &frameinfo)
            if ret:
                raise JpeglsError('charls_jpegls_decoder_get_frame_info', ret)

            ret = charls_jpegls_decoder_get_interleave_mode(
                decoder,
                &interleave_mode
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_decoder_get_interleave_mode', ret
                )

            with gil:
                if frameinfo.bits_per_sample <= 8:
                    dtype = numpy.uint8
                    itemsize = 1
                elif frameinfo.bits_per_sample <= 16:
                    dtype = numpy.uint16
                    itemsize = 2
                else:
                    raise ValueError(
                        'JpegLs bits_per_sample not supported: {}'.format(
                            frameinfo.bits_per_sample
                        )
                    )

                if frameinfo.component_count == 1:
                    shape = (
                        frameinfo.height,
                        frameinfo.width
                    )
                    strides = (
                        frameinfo.width * itemsize,
                        itemsize
                    )
                elif interleave_mode == CHARLS_INTERLEAVE_MODE_NONE:
                    # planar
                    shape = (
                        frameinfo.component_count,
                        frameinfo.height,
                        frameinfo.width
                    )
                    strides = (
                        itemsize * frameinfo.width * frameinfo.height,
                        itemsize * frameinfo.width,
                        itemsize
                    )
                else:
                    # contig
                    # CHARLS_INTERLEAVE_MODE_LINE or
                    # CHARLS_INTERLEAVE_MODE_SAMPLE
                    shape = (
                        frameinfo.height,
                        frameinfo.width,
                        frameinfo.component_count
                    )
                    strides = (
                        itemsize * frameinfo.component_count * frameinfo.width,
                        itemsize * frameinfo.component_count,
                        itemsize
                    )
                out = _create_array(out, shape, dtype, strides=strides)
                dst = out
                dstsize = dst.nbytes

            ret = charls_jpegls_decoder_decode_to_buffer(
                decoder,
                <void*> dst.data,
                <size_t> dstsize,
                0
            )

        if ret:
            raise JpeglsError('charls_jpegls_decoder_decode_to_buffer', ret)

    finally:
        if decoder != NULL:
            charls_jpegls_decoder_destroy(decoder)

    if (
        frameinfo.component_count > 1
        and interleave_mode == CHARLS_INTERLEAVE_MODE_NONE
    ):
        out = numpy.moveaxis(out, 0, -1)

    return out
def jpegls_decode_header(data):
    """Return decoded JPEGLS image."""
    cdef:
        const uint8_t[::1] src = data
        ssize_t srcsize = src.size
        ssize_t dstsize
        ssize_t itemsize = 0
        charls_jpegls_errc ret
        charls_jpegls_decoder* decoder = NULL
        charls_interleave_mode interleave_mode
        charls_frame_info frameinfo
        charls_color_transformation color_transformation
        charls_spiff_header spiff_header
        int32_t header_found
        int32_t near_lossless



    bits_allocated=0
    bits_stored=0
    high_bit=0
    try:
        with nogil:
            decoder = charls_jpegls_decoder_create()
            if decoder == NULL:
                raise JpeglsError('charls_jpegls_decoder_create', None)

            ret = charls_jpegls_decoder_set_source_buffer(
                decoder,
                <void*> &src[0],
                <size_t> srcsize
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_decoder_set_source_buffer', ret
                )

            ret = charls_jpegls_decoder_read_spiff_header(
                decoder,
                &spiff_header,
                &header_found
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_decoder_read_spiff_header', ret
                )

            ret = charls_jpegls_decoder_read_header(decoder)
            if ret:
                raise JpeglsError('charls_jpegls_decoder_read_header', ret)

            ret = charls_jpegls_decoder_get_frame_info(decoder, &frameinfo)
            if ret:
                raise JpeglsError('charls_jpegls_decoder_get_frame_info', ret)

            ret = charls_jpegls_decoder_get_interleave_mode(
                decoder,
                &interleave_mode
            )
            if ret:
                raise JpeglsError(
                    'charls_jpegls_decoder_get_interleave_mode', ret
                )

            with gil:
                if frameinfo.bits_per_sample <= 8:
                    dtype = numpy.uint8
                    itemsize = 1
                    bits_allocated=8
                elif frameinfo.bits_per_sample <= 16:
                    dtype = numpy.uint16
                    itemsize = 2
                    bits_allocated=16
                else:
                    raise ValueError(
                        'JpegLs bits_per_sample not supported: {}'.format(
                            frameinfo.bits_per_sample
                        )
                    )

                bits_stored=frameinfo.bits_per_sample
                high_bit=frameinfo.bits_per_sample-1
                charls_jpegls_decoder_get_near_lossless(decoder,0,&near_lossless)


    finally:
        if decoder != NULL:
            charls_jpegls_decoder_destroy(decoder)


    ## seup the dicom metada
    dcm_meta = DCMPixelMeta()
    dcm_meta.samples_per_pixel = frameinfo.component_count
    if dcm_meta.samples_per_pixel == 1:
        dcm_meta.photometric_interpretation = "MONOCHROME2"
    elif dcm_meta.samples_per_pixel == 3:
        ## do something from the colorspace
        if spiff_header.colorspace == 3:

                dcm_meta.photometric_interpretation = "YBR_FULL"

        elif spiff_header.colorspace == 10:
            dcm_meta.photometric_interpretation = "RGB"

        else:
            dcm_meta.photometric_interpretation="UNKNOWN %d"%spiff_header.colorspace

    dcm_meta.rows = frameinfo.height
    dcm_meta.columns = frameinfo.width
    dcm_meta.bits_allocated=bits_allocated
    dcm_meta.bits_stored = bits_stored
    dcm_meta.pixel_representation=0 ## check this
    dcm_meta.high_bit=high_bit
    if dcm_meta.samples_per_pixel != 3:
        dcm_meta.planar_configuration=-1
    else:
        dcm_meta.planar_configuration=0
    dcm_meta.pixel_data_format="int"

    if near_lossless == 0:
        dcm_meta.transfer_syntax_uid="1.2.840.10008.1.2.​4.​80"
    else:
        dcm_meta.transfer_syntax_uid="1.2.840.10008.1.2.​4.​81"

    return dcm_meta