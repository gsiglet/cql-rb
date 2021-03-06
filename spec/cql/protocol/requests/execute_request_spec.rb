# encoding: ascii-8bit

require 'spec_helper'


module ExecuteRequestSpec
  module ItEncodes
    def it_encodes(description, type, value, expected_bytes)
      it("encodes #{description}") do
        bytes = encode_value(type, value)
        bytes.should eql_bytes(expected_bytes)
      end
    end
  end
end

module Cql
  module Protocol
    describe ExecuteRequest do
      let :id do
        "\xCAH\x7F\x1Ez\x82\xD2<N\x8A\xF35Qq\xA5/"
      end

      let :column_metadata do
        [
          ['ks', 'tbl', 'col1', :varchar],
          ['ks', 'tbl', 'col2', :int],
          ['ks', 'tbl', 'col3', :varchar]
        ]
      end

      let :values do
        ['hello', 42, 'foo']
      end

      describe '#initialize' do
        it 'raises an error when the metadata and values don\'t have the same size' do
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42], true, :each_quorum, nil, nil, nil, false) }.to raise_error(ArgumentError)
        end

        it 'raises an error when the consistency is nil' do
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, nil, nil, nil, nil, false) }.to raise_error(ArgumentError)
        end

        it 'raises an error when the consistency is invalid' do
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :hello, nil, nil, nil, false) }.to raise_error(ArgumentError)
        end

        it 'raises an error when the serial consistency is invalid' do
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :quorum, :foo, nil, nil, false) }.to raise_error(ArgumentError)
        end

        it 'raises an error when paging state is given but no page size' do
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :quorum, nil, nil, 'foo', false) }.to raise_error(ArgumentError)
        end

        it 'raises an error for unsupported column types' do
          column_metadata[2][3] = :imaginary
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :each_quorum, nil, nil, nil, false) }.to raise_error(UnsupportedColumnTypeError)
        end

        it 'raises an error for unsupported column collection types' do
          column_metadata[2][3] = [:imaginary, :varchar]
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42, ['foo']], true, :each_quorum, nil, nil, nil, false) }.to raise_error(UnsupportedColumnTypeError)
        end

        it 'raises an error when collection values are not enumerable' do
          column_metadata[2][3] = [:set, :varchar]
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :each_quorum, nil, nil, nil, false) }.to raise_error(InvalidValueError)
        end

        it 'raises an error when it cannot encode the argument' do
          expect { ExecuteRequest.new(id, column_metadata, ['hello', 'not an int', 'foo'], true, :each_quorum, nil, nil, nil, false) }.to raise_error(TypeError, /cannot be encoded as INT/)
        end
      end

      describe '#write' do
        def encode_value(type, value)
          request = described_class.new(id, [['ks', 'tbl', 'col', type]], [value], true, :one, nil, nil, nil, false)
          buffer = request.write(1, CqlByteBuffer.new)
          buffer.discard(2 + 16 + 2)
          buffer.read(buffer.read_int)
        end

        context 'when the protocol version is 1' do
          let :frame_bytes do
            ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :each_quorum, nil, nil, nil, false).write(1, CqlByteBuffer.new)
          end

          it 'writes the statement ID' do
            frame_bytes.to_s[0, 18].should == "\x00\x10\xCAH\x7F\x1Ez\x82\xD2<N\x8A\xF35Qq\xA5/"
          end

          it 'writes the number of bound variables' do
            frame_bytes.to_s[18, 2].should == "\x00\x03"
          end

          it 'writes the bound variables' do
            frame_bytes.to_s[20, 24].should == "\x00\x00\x00\x05hello\x00\x00\x00\x04\x00\x00\x00\x2a\x00\x00\x00\x03foo"
          end

          it 'writes the consistency' do
            frame_bytes.to_s[44, 999].should == "\x00\x07"
          end
        end

        context 'when the protocol version is 2' do
          let :frame_bytes do
            ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :each_quorum, nil, nil, nil, false).write(2, CqlByteBuffer.new)
          end

          it 'writes the statement ID' do
            frame_bytes.to_s[0, 18].should == "\x00\x10\xCAH\x7F\x1Ez\x82\xD2<N\x8A\xF35Qq\xA5/"
          end

          it 'writes the consistency' do
            frame_bytes.to_s[18, 2].should == "\x00\x07"
          end

          it 'writes flags saying that there will be bound values values' do
            frame_bytes.to_s[20, 1].should == "\x01"
          end

          it 'does not write the bound values flag when there are no values, and does not write anything more' do
            frame_bytes = ExecuteRequest.new(id, [], [], true, :each_quorum, nil, nil, nil, false).write(2, CqlByteBuffer.new)
            frame_bytes.to_s[20, 999].should == "\x00"
          end

          it 'writes flags saying that the result doesn\'t need to contain metadata' do
            frame_bytes = ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], false, :each_quorum, nil, nil, nil, false).write(2, CqlByteBuffer.new)
            frame_bytes.to_s[20, 1].should == "\x03"
          end

          it 'writes the number of bound values' do
            frame_bytes.to_s[21, 2].should == "\x00\x03"
          end

          it 'writes the bound values' do
            frame_bytes.to_s[23, 999].should == "\x00\x00\x00\x05hello\x00\x00\x00\x04\x00\x00\x00\x2a\x00\x00\x00\x03foo"
          end

          it 'sets the serial flag and includes the serial consistency' do
            frame_bytes = ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], false, :each_quorum, :local_serial, false).write(2, CqlByteBuffer.new)
            frame_bytes.to_s[20, 1].should == "\x13"
            frame_bytes.to_s[47, 2].should == "\x00\x09"
          end

          it 'writes the page size flag and page size' do
            frame_bytes = ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :one, nil, 10, nil, false).write(2, CqlByteBuffer.new)
            (frame_bytes.to_s[20, 1].ord & 0x04).should == 0x04
            frame_bytes.to_s[47, 4].should == "\x00\x00\x00\x0a"
          end

          it 'writes the page size and paging state flag and the page size and paging state' do
            frame_bytes = ExecuteRequest.new(id, column_metadata, ['hello', 42, 'foo'], true, :one, nil, 10, 'foobar', false).write(2, CqlByteBuffer.new)
            (frame_bytes.to_s[20, 1].ord & 0x0c).should == 0x0c
            frame_bytes.to_s[47, 4].should == "\x00\x00\x00\x0a"
            frame_bytes.to_s[51, 10].should == "\x00\x00\x00\x06foobar"
          end
        end

        context 'with scalar types' do
          extend ExecuteRequestSpec::ItEncodes

          it_encodes 'ASCII strings', :ascii, 'test', "test"
          it_encodes 'BIGINTs', :bigint, 1012312312414123, "\x00\x03\x98\xB1S\xC8\x7F\xAB"
          it_encodes 'BLOBs', :blob, "\xab\xcd", "\xab\xcd"
          it_encodes 'false BOOLEANs', :boolean, false, "\x00"
          it_encodes 'true BOOLEANs', :boolean, true, "\x01"
          it_encodes 'DECIMALs', :decimal, BigDecimal.new('1042342234234.123423435647768234'), "\x00\x00\x00\x12\r'\xFDI\xAD\x80f\x11g\xDCfV\xAA"
          it_encodes 'DOUBLEs', :double, 10000.123123123, "@\xC3\x88\x0F\xC2\x7F\x9DU"
          it_encodes 'FLOATs', :float, 12.13, "AB\x14{"
          it_encodes 'IPv4 INETs', :inet, IPAddr.new('8.8.8.8'), "\x08\x08\x08\x08"
          it_encodes 'IPv6 INETs', :inet, IPAddr.new('::1'), "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01"
          it_encodes 'INTs', :int, 12348098, "\x00\xBCj\xC2"
          it_encodes 'TEXTs from UTF-8 strings', :text, 'ümlaut'.force_encoding(::Encoding::UTF_8), "\xc3\xbcmlaut"
          it_encodes 'TIMESTAMPs from Times', :timestamp, Time.at(1358013521.123), "\x00\x00\x01</\xE9\xDC\xE3"
          it_encodes 'TIMESTAMPs from floats', :timestamp, 1358013521.123, "\x00\x00\x01</\xE9\xDC\xE3"
          it_encodes 'TIMESTAMPs from integers', :timestamp, 1358013521, "\x00\x00\x01</\xE9\xDCh"
          it_encodes 'TIMEUUIDs', :timeuuid, Uuid.new('a4a70900-24e1-11df-8924-001ff3591711'), "\xA4\xA7\t\x00$\xE1\x11\xDF\x89$\x00\x1F\xF3Y\x17\x11"
          it_encodes 'UUIDs', :uuid, Uuid.new('cfd66ccc-d857-4e90-b1e5-df98a3d40cd6'), "\xCF\xD6l\xCC\xD8WN\x90\xB1\xE5\xDF\x98\xA3\xD4\f\xD6"
          it_encodes 'VARCHAR from UTF-8 strings', :varchar, 'hello'.force_encoding(::Encoding::UTF_8), 'hello'
          it_encodes 'positive VARINTs', :varint, 1231312312331283012830129382342342412123, "\x03\x9EV \x15\f\x03\x9DK\x18\xCDI\\$?\a["
          it_encodes 'negative VARINTs', :varint, -234234234234, "\xC9v\x8D:\x86"
        end

        context 'with collection types' do
          extend ExecuteRequestSpec::ItEncodes

          it_encodes 'LIST<TIMESTAMP>', [:list, :timestamp], [Time.at(1358013521.123)], "\x00\x01" + "\x00\x08\x00\x00\x01</\xE9\xDC\xE3"
          it_encodes 'LIST<BOOLEAN>', [:list, :boolean], [true, false, true, true], "\x00\x04" + "\x00\x01\x01" + "\x00\x01\x00"  + "\x00\x01\x01" + "\x00\x01\x01"
          it_encodes 'MAP<UUID,INT>', [:map, :uuid, :int], {Uuid.new('cfd66ccc-d857-4e90-b1e5-df98a3d40cd6') => 45345, Uuid.new('a4a70900-24e1-11df-8924-001ff3591711') => 98765}, "\x00\x02" + "\x00\x10\xCF\xD6l\xCC\xD8WN\x90\xB1\xE5\xDF\x98\xA3\xD4\f\xD6" + "\x00\x04\x00\x00\xb1\x21" + "\x00\x10\xA4\xA7\t\x00$\xE1\x11\xDF\x89$\x00\x1F\xF3Y\x17\x11" + "\x00\x04\x00\x01\x81\xcd"
          it_encodes 'MAP<ASCII,BLOB>', [:map, :ascii, :blob], {'hello' => 'world', 'one' => "\x01", 'two' => "\x02"}, "\x00\x03" + "\x00\x05hello" + "\x00\x05world" + "\x00\x03one" + "\x00\x01\x01" + "\x00\x03two" + "\x00\x01\x02"
          it_encodes 'SET<INT> from Sets', [:set, :int], Set.new([13, 3453, 456456, 123, 768678]), "\x00\x05" + "\x00\x04\x00\x00\x00\x0d" + "\x00\x04\x00\x00\x0d\x7d" + "\x00\x04\x00\x06\xf7\x08" + "\x00\x04\x00\x00\x00\x7b" + "\x00\x04\x00\x0b\xba\xa6"
          it_encodes 'SET<INT> from arrays', [:set, :int], [13, 3453, 456456, 123, 768678], "\x00\x05" + "\x00\x04\x00\x00\x00\x0d" + "\x00\x04\x00\x00\x0d\x7d" + "\x00\x04\x00\x06\xf7\x08" + "\x00\x04\x00\x00\x00\x7b" + "\x00\x04\x00\x0b\xba\xa6"
          it_encodes 'SET<VARCHAR> from Sets', [:set, :varchar], Set.new(['foo', 'bar', 'baz']), "\x00\x03" + "\x00\x03foo" + "\x00\x03bar" + "\x00\x03baz"
          it_encodes 'SET<VARCHAR> from arrays', [:set, :varchar], ['foo', 'bar', 'baz'], "\x00\x03" + "\x00\x03foo" + "\x00\x03bar" + "\x00\x03baz"
        end

        context 'with user defined types' do
          context 'with a flat UDT' do
            let :type do
              [:udt, {'street' => :text, 'city' => :text, 'zip' => :int}]
            end

            let :value do
              {'street' => '123 Some St.', 'city' => 'Frans Sanisco', 'zip' => 76543}
            end

            it 'encodes a hash into bytes' do
              bytes = encode_value(type, value)
              bytes.should eql_bytes(
                "\x00\x00\x00\f123 Some St." +
                "\x00\x00\x00\rFrans Sanisco" +
                "\x00\x00\x00\x04\x00\x01*\xFF"
              )
            end
          end

          context 'with a UDT as a MAP value' do
            let :type do
              [:map, :varchar, [:udt, {'street' => :text, 'city' => :text, 'zip' => :int}]]
            end

            let :value do
              {'secret_lair' => {'street' => '4 Some Other St.', 'city' => 'Gos Latos', 'zip' => 87654}}
            end

            it 'encodes a hash into bytes' do
              bytes = encode_value(type, value)
              bytes.should eql_bytes(
                "\x00\x01" +
                "\x00\vsecret_lair" +
                "\x00)" +
                "\x00\x00\x00\x104 Some Other St." +
                "\x00\x00\x00\tGos Latos" +
                "\x00\x00\x00\x04\x00\x01Vf"
              )
            end
          end

          context 'with nested UDTs' do
            let :type do
              [:set, [:udt, {'name' => :text, 'addresses' => [:list, [:udt, {'street' => :text, 'city' => :text, 'zip' => :int}]]}]]
            end

            let :value do
              Set.new([
                {
                  'name' => 'Acme Corp',
                  'addresses' => [
                    {'street' => '1 St.', 'city' => '1 City', 'zip' => 11111},
                    {'street' => '2 St.', 'city' => '2 City', 'zip' => 22222}
                  ]
                },
                {
                  'name' => 'Foo Inc.',
                  'addresses' => [
                    {'street' => '3 St.', 'city' => '3 City', 'zip' => 33333}
                  ]
                }
              ])
            end

            it 'encodes a hash into bytes' do
              bytes = encode_value(type, value)
              bytes.should eql_bytes(
                "\x00\x02" +
                "\x00S" +
                "\x00\x00\x00\tAcme Corp" +
                "\x00\x00\x00B" +
                "\x00\x00\x00\x02" +
                "\x00\x00\x00\e" +
                "\x00\x00\x00\x051 St." +
                "\x00\x00\x00\x061 City" +
                "\x00\x00\x00\x04\x00\x00+g" +
                "\x00\x00\x00\e" +
                "\x00\x00\x00\x052 St." +
                "\x00\x00\x00\x062 City" +
                "\x00\x00\x00\x04\x00\x00V\xCE" +
                "\x003" +
                "\x00\x00\x00\bFoo Inc." +
                "\x00\x00\x00#" +
                "\x00\x00\x00\x01" +
                "\x00\x00\x00\e" +
                "\x00\x00\x00\x053 St." +
                "\x00\x00\x00\x063 City" +
                "\x00\x00\x00\x04\x00\x00\x825"
              )
            end
          end
        end

        context 'with custom types' do
          let :type do
            [:custom, 'com.example.CustomType']
          end

          let :value do
            "\x01\x02\x03\x04\x05"
          end

          it 'encodes a byte string into bytes' do
            bytes = encode_value(type, value)
            bytes.should eql_bytes("\x01\x02\x03\x04\x05")
          end
        end
      end

      describe '#to_s' do
        it 'returns a pretty string' do
          request = ExecuteRequest.new(id, column_metadata, values, true, :each_quorum, nil, nil, nil, false)
          request.to_s.should == 'EXECUTE ca487f1e7a82d23c4e8af3355171a52f ["hello", 42, "foo"] EACH_QUORUM'
        end
      end

      describe '#eql?' do
        it 'returns true when the ID, metadata, values and consistency are the same' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e1.should eql(e2)
        end

        it 'returns false when the ID is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id.reverse, column_metadata, values, true, :one, nil, nil, nil, false)
          e1.should_not eql(e2)
        end

        it 'returns false when the metadata is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata.reverse, values, true, :one, nil, nil, nil, false)
          e1.should_not eql(e2)
        end

        it 'returns false when the values are different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values.reverse, true, :one, nil, nil, nil, false)
          e1.should_not eql(e2)
        end

        it 'returns false when the consistency is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :two, nil, nil, nil, false)
          e1.should_not eql(e2)
        end

        it 'returns false when the serial consistency is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, :serial, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :one, :local_serial, nil, nil, false)
          e1.should_not eql(e2)
        end

        it 'returns false when the page size is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, 10, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, 20, nil, false)
          e1.should_not eql(e2)
        end

        it 'returns false when the paging state is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, 10, 'foo', false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, 10, 'bar', false)
          e1.should_not eql(e2)
        end

        it 'is aliased as ==' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e1.should == e2
        end
      end

      describe '#hash' do
        it 'has the same hash code as another identical object' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e1.hash.should == e2.hash
        end

        it 'does not have the same hash code when the ID is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id.reverse, column_metadata, values, true, :one, nil, nil, nil, false)
          e1.hash.should_not == e2.hash
        end

        it 'does not have the same hash code when the metadata is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata.reverse, values, true, :one, nil, nil, nil, false)
          e1.hash.should_not == e2.hash
        end

        it 'does not have the same hash code when the values are different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values.reverse, true, :one, nil, nil, nil, false)
          e1.hash.should_not == e2.hash
        end

        it 'does not have the same hash code when the consistency is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :two, nil, nil, nil, false)
          e1.hash.should_not == e2.hash
        end

        it 'does not have the same hash code when the serial consistency is different' do
          e1 = ExecuteRequest.new(id, column_metadata, values, true, :one, nil, nil, nil, false)
          e2 = ExecuteRequest.new(id, column_metadata, values, true, :one, :serial, nil, nil, false)
          e1.hash.should_not == e2.hash
        end
      end
    end
  end
end
