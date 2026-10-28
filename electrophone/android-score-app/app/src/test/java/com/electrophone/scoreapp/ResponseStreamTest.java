package com.electrophone.scoreapp;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public final class ResponseStreamTest {
    @Test
    public void findsPongAfterStaleErrorsWithoutLineEnding() throws Exception {
        ResponseStream responses = new ResponseStream(new ByteArrayInputStream(
                "ERRERRPONG".getBytes(StandardCharsets.US_ASCII)));
        assertEquals(
                ResponseStream.PONG,
                responses.readToken(tokens(ResponseStream.PONG), 500));
    }

    @Test
    public void readsConcatenatedResponsesOneTokenAtATime() throws Exception {
        ResponseStream responses = new ResponseStream(new ByteArrayInputStream(
                "OKERRFULL".getBytes(StandardCharsets.US_ASCII)));
        Set<String> accepted = tokens(
                ResponseStream.OK, ResponseStream.ERR, ResponseStream.FULL);
        assertEquals(ResponseStream.OK, responses.readToken(accepted, 500));
        assertEquals(ResponseStream.ERR, responses.readToken(accepted, 500));
        assertEquals(ResponseStream.FULL, responses.readToken(accepted, 500));
    }

    @Test
    public void readsNewProtocolLineAfterLegacyPongLineEnding() throws Exception {
        ResponseStream responses = new ResponseStream(new ByteArrayInputStream(
                "\r\nVERSION 2\r\n".getBytes(StandardCharsets.US_ASCII)));
        assertEquals(
                "VERSION 2",
                responses.readLineOrToken(tokens(ResponseStream.ERR), 500));
    }

    @Test
    public void readsLegacyErrorWithoutLineEnding() throws Exception {
        ResponseStream responses = new ResponseStream(new ByteArrayInputStream(
                "ERR".getBytes(StandardCharsets.US_ASCII)));
        assertEquals(
                ResponseStream.ERR,
                responses.readLineOrToken(tokens(ResponseStream.ERR), 500));
    }

    @Test
    public void readsBinaryDumpHeaderAndEventBytesInOrder() throws Exception {
        ResponseStream responses = new ResponseStream(new ByteArrayInputStream(
                new byte[]{(byte) 0xA5, 0x5A, 0x00, 0x01, 0x00, 0x03, 0x21, 0x40}));
        assertEquals(0xA5, responses.readByte(500));
        assertEquals(0x5A, responses.readByte(500));
        assertEquals(0x00, responses.readByte(500));
        assertEquals(0x01, responses.readByte(500));
        assertEquals(0x00, responses.readByte(500));
        assertEquals(0x03, responses.readByte(500));
        assertEquals(0x21, responses.readByte(500));
        assertEquals(0x40, responses.readByte(500));
    }

    @Test
    public void skipsPreviousCommandLineEndingBeforeBinaryMagic() throws Exception {
        ResponseStream responses = new ResponseStream(new ByteArrayInputStream(
                new byte[]{'\r', '\n', (byte) 0xA5, 0x5A}));
        assertEquals(0xA5, responses.readByteSkippingLineEndings(500));
        assertEquals(0x5A, responses.readByte(500));
    }

    private static Set<String> tokens(String... values) {
        return new HashSet<>(Arrays.asList(values));
    }
}
