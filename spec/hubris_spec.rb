# encoding: ASCII-8BIT
load File.dirname(__FILE__) + '/spec_helper.rb'
require "hubris"
Hubris.add_packages %w(base)

# # just want to check it's actually possible to load a library dynamically
# describe "dlload" do
#   it "actually builds and loads a C level dylib stupidly" do
#     system "cd sample; make"
#     `cd sample; ruby hsload.rb`.chomp.should eql("144")
#   end
# end

class Target
  def foo_local
    14
  end
end

Signal.trap("INT", 'EXIT');

describe "Target" do  
  it "whines like a little baby when you pass it bad haskell" do
    lambda{ class Foo; hubris :inline => "broken _ = (1 + \"a string\")", :no_strict => true; end}.should raise_error(HaskellError)
  end

  it "ignores a comment" do
    lambda {
      class Foo; hubris :inline => "--blah blah blah
{- another silly comment -}
foo :: Bool -> Bool
foo True = False
foo False = True"; end
    }.should_not raise_error
  end

  it "sings like a golden bird when you treat it right, aw yeah" do
    #    t = Target.new
    #    lambda { t.inline("working _ = T_FIXNUM (1+2)", { :no_strict => true }) }.should_not raise_error
    lambda { class Foo; hubris :inline => "working :: Integer -> Integer; working a = 2*a"; end}.should_not raise_error
  end


  #   it "handles booleans" do
  #     class Bar
  #       hubris :inline => "my_negate True = False;my_negate False = True", :no_strict => true
  #     end
  #     t = Bar.new
  #     # puts t.methods
  #     t.my_negate(false).should eql(true)
  #     t.my_negate(true).should eql(false)
  #     lambda{ t.my_negate("Banana")}.should raise_error
  #   end
  
  it "handles doubles" do
    class Doubler
      hubris :inline => "triple :: Double -> Double; triple a = a*3.0", :no_strict => true
    end
    d = Doubler.new

    d.triple(3.4).should eql(10.2)
  end
end

describe "Strings" do
  it "can reverse a string" do 
    class Stringer
      hubris :inline => "import Data.ByteString; my_reverse::ByteString->ByteString; my_reverse s = Data.ByteString.reverse s", :no_strict => true
    end
    Stringer.new.my_reverse("foot").should eql("toof")
  end
end

describe "BigInt" do
  it "handles BigInts" do
    class Bigint
      hubris :inline => "big_inc :: Integer -> Integer; big_inc i = i + 1"
    end
    b = Bigint.new
    b.big_inc(10000000000000000).should eql(10000000000000001)
    b.big_inc(1).should eql(2)
  end
end

describe 'Multiple' do
  # this one requires multiple lib linking
  it "can load multiple libs" do
    class Multiple
      def foo_local
        14
      end
      hubris :inline => "mydouble::Int->Int; mydouble i =(i + i)" 
      hubris :inline => "incr::Int->Int;incr i = 1+i"
    end
    t=Multiple.new
    t.mydouble(1).should eql(2)
    # and it doesn't wipe out other methods on the class
    t.foo_local.should eql(14)
    t.incr(3).should eql(4)
    # FIXME this one is waiting for support of Control.Exception in
    # JHC
    # lambda { t.mydouble(2.3)}.should raise_error(HaskellError)
    # Fooclever.mydouble(2.3).should raise_error(RuntimeError)
  end
end

describe 'Arrays' do
  it "can use arrays sensibly" do
    class ArrayTest
      hubris :inline => "mylength :: [Int] -> Int; mylength [] = 0; mylength (_:xs) = 1 + mylength xs"
    end
    
    ArrayTest.new.mylength([1,2,3,4]).should eql(4)
  end
  it "returns a haskell list as  an array" do
    class ArrayTest2
      hubris :inline => "elts :: Int -> [Int]; elts i = take i [1..]"
    end
    t=ArrayTest2.new
    t.elts(5).should eql([1,2,3,4,5])
    lambda { t.elts("A Banana")}.should raise_error(HaskellError)
  end
  it "uses a Haskell array" do
    class ArrayTest3
      hubris :inline => "import Data.Array.IArray; larr :: Int -> Array Int Int; larr x = listArray (0,x-1) [1..x]"
    end
    ArrayTest3.new.larr(7).should == [1,2,3,4,5,6,7]
  end
end

describe 'MaybeOut' do
  it "passes back maybes" do
    class Maybe
      hubris :inline => "foo:: Int -> Maybe Int; foo 1 = Just 1; foo _ = Nothing"
    end
    m=Maybe.new
    m.foo(1).should == 1
    m.foo(2).should == nil
    lambda{ m.foo("blah") }.should raise_error(HaskellError)
  end
end
describe "MaybeIn" do
  it "takes in Maybes" do
    class MaybeIn
      hubris :inline => "foo:: Maybe Int -> Int; foo (Just n) = 2*n; foo Nothing = 0"
    end
    class MaybeLazy
      hubris :inline => "foo:: Maybe Int -> Int; foo (Just _) = 1; foo Nothing = 0"
    end
    m=MaybeIn.new
#    m.foo(1).should == 1
#    m.foo(20).should == 1
#    m.foo(nil).should == 2
    lambda{ m.foo("blah") }.should raise_error(HaskellError)
    # here's a tricky bit: in the previous example, we had to look at the value of the
    # Maybe, so the exception got triggered.
    # Here, however, we're not passing in a nil, so we get a "Just 'something'", and never
    # deeply examine the something. Arguably, it would be less surprising if we always looked
    # deeply into it, but it's up for debate. TODO
    
    lazy = MaybeLazy.new
    lazy.foo("blah").should == 1
  end
end

describe 'Hashes' do
  it "can move a Haskell map to ruby" do
    class HaskellMap
      hubris :inline => "import Data.Map ; h :: Int -> Map Int Int; h n = Data.Map.fromList $ zip [1..n] [n, n-1 .. 1]"
    end
    rh=HaskellMap.new.h(3)
    rh[3].should == 1
    rh[2].should == 2
    rh[1].should == 3
  end
  
  it "can move a ruby map to haskell" do
    class RubyMap
      hubris :inline => "import Data.Map; h :: Map Int Int -> Maybe Int; h m = Data.Map.lookup 10 m"
    end
    rb = RubyMap.new
    rb.h({8 => 100, 2 => 7}).should eql(nil)
    rb.h({10 => 100, 2 => 7}).should eql(100)
  end
  
end



describe "Blocks" do
  
  it "can be called in a block" do
    class T2
      hubris :inline => "foo::Integer->Integer;foo i = -i"
    end
    t = T2.new
    (1..2).each do |x|
      t.foo(x).should eql(0-x)
    end
  end
end

describe "Overwrite" do
  it "can overwrite old functions" do
    class Overlapping
      hubris :inline => "myid::Int -> Int; myid i = i"
      hubris :inline => "myid::Int -> Int; myid i = i+1"
    end
    t=Overlapping.new
    t.myid(1).should eql(2)
  end
  
  
end

describe "Exceptions" do
  it "throws an exception on partial match" do
    class BoolFunc
      hubris :inline => "mynot :: Bool -> Bool; mynot True = False; mynot False = True"
    end
    t=BoolFunc.new
    lambda{ t.mynot(true) }.should_not raise_error(HaskellError)
    lambda{ puts t.mynot("blah") }.should raise_error(HaskellError)
  end

  it "catches incomplete code unless you turn no_strict on" do
    lambda {
      class Incomplete
        hubris :inline => "incomplete :: Int -> Bool; incomplete 1 = True"
      end
    }.should raise_error(HaskellError)
    lambda { 
      class IncompleteButOk
        hubris :inline => "incomplete :: Int -> Bool; incomplete 1 = True" , :no_strict => true
      end
    }.should_not raise_error()
    
  end

end

describe 'Idempotence' do 
  it "doesn't affect other modules" do
    class Existing
    end

    class Target
      hubris :inline => "fun :: Int -> Int; fun x = x+1"
    end
    e=Existing.new
    t=Target.new
    lambda{ e.fun(10)}.should raise_error(NoMethodError)
    lambda{ t.fun(10)}.should_not raise_error(NoMethodError)
    t.fun(10).should eql(11)
  end
  
  it "can insert the same code into two ruby modules" do
    class Foo10
      hubris :inline => "foobar::Double -> Double;foobar n = n+1.0"
    end
    class Foo11
      hubris :inline => "foobar::Double -> Double;foobar n = n+1.0"
    end

    Foo10.new.foobar(1.0).should eql(2.0)
    Foo11.new.foobar(1.0).should eql(2.0)

  end
end

describe 'Realworld' do
  it "can handle the bytestring lib" do

    class ByteString
      hubris :module => "Data.ByteString"
    end
    
    b = ByteString.new
    b.sort("zabcdfg").should == "abcdfgz"
  end
  
  it "can import zlib" do
    pending "Not doing the right thing with embedded nulls yet"
    class ZLib
      hubris :module => 'Codec.Compression.GZip', :packages => ['zlib', 'bytestring']
    end
    z=ZLib.new
    w="osatnoensauhoestnuhoastuhoeatnuhosnueohnsauostneo"
    puts w.encoding
    x=z.compress(w)
    x.each_byte {|c| print c, ' ' }
    puts "length|#{x.length}|"
    puts "second"
    z.decompress(z.compress(w)).should eql(w)
  end
  
end

describe 'Performance' do
  def be_quick
    simple_matcher("a small duration") { |given| given < 0.1 }
  end

  it "caches its output" do
    # only relevant for inlining
    
    t=Target.new
    class First
      hubris :inline => "foobar::Int->Int; foobar a = a"
    end
    before = Time.now   
    class Second
      hubris :inline => "foobar::Int->Int; foobar a = a"
    end
    after = Time.now    

    (after-before).should be_quick
  end

  it "behaves memory-wise" do
    # so, how on earth do we do this? Conceptually, we want to bind a function,
    # call it many times, and assert that memory use is (eventually) constant
    # possible approaches
    #   - caveman: ps, grep etc.
    #   - galois style (is that haskell-dtrace?)
  end
  
  it "behaves concurrently" do
    # create a bunch of ruby threads which all call a given Haskell function
    # repeatedly. Checks that we get the right result, and that we don't crash.
    pending "Don't wanna run this every time"
    no_threads = 10
    reps=1000
    class ConcTest
      hubris :inline => "sumInts :: Int -> Int; sumInts n = sum [0..n]"
    end
    t = ConcTest.new
    
    res = (0..no_threads).map { |n| (0..n).inject { |sum,n| sum+n } }
    threads = []
    lambda {
      (0..no_threads).each { |n|
        threads << Thread.start(n) { |x|
          reps.times { t.sumInts(x).should eql(res[x]) }
        }
      }
      threads.each { |t| t.join }
    }.should_not raise_error
  end
end
