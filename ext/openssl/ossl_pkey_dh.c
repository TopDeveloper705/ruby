/*
 * 'OpenSSL for Ruby' project
 * Copyright (C) 2001-2002  Michal Rokos <m.rokos@sh.cvut.cz>
 * All rights reserved.
 */
/*
 * This program is licensed under the same licence as Ruby.
 * (See the file 'LICENCE'.)
 */
#include "ossl.h"

#if !defined(OPENSSL_NO_DH)

#define GetPKeyDH(obj, pkey) do { \
    GetPKey((obj), (pkey)); \
    if (EVP_PKEY_base_id(pkey) != EVP_PKEY_DH) { /* PARANOIA? */ \
	ossl_raise(rb_eRuntimeError, "THIS IS NOT A DH!") ; \
    } \
} while (0)
#define GetDH(obj, dh) do { \
    EVP_PKEY *_pkey; \
    GetPKeyDH((obj), _pkey); \
    (dh) = EVP_PKEY_get0_DH(_pkey); \
} while (0)

/*
 * Classes
 */
VALUE cDH;
VALUE eDHError;

/*
 * Private
 */
/*
 * call-seq:
 *   DH.new -> dh
 *   DH.new(string) -> dh
 *   DH.new(size [, generator]) -> dh
 *
 * Creates a new instance of OpenSSL::PKey::DH.
 *
 * If called without arguments, an empty instance without any parameter or key
 * components is created. Use #set_pqg to manually set the parameters afterwards
 * (and optionally #set_key to set private and public key components).
 *
 * If a String is given, tries to parse it as a DER- or PEM- encoded parameters.
 * See also OpenSSL::PKey.read which can parse keys of any kinds.
 *
 * The DH.new(size [, generator]) form is an alias of DH.generate.
 *
 * +string+::
 *   A String that contains the DER or PEM encoded key.
 * +size+::
 *   See DH.generate.
 * +generator+::
 *   See DH.generate.
 *
 * Examples:
 *   # Creating an instance from scratch
 *   dh = DH.new
 *   dh.set_pqg(bn_p, nil, bn_g)
 *
 *   # Generating a parameters and a key pair
 *   dh = DH.new(2048) # An alias of DH.generate(2048)
 *
 *   # Reading DH parameters
 *   dh = DH.new(File.read('parameters.pem')) # -> dh, but no public/private key yet
 *   dh.generate_key! # -> dh with public and private key
 */
static VALUE
ossl_dh_initialize(int argc, VALUE *argv, VALUE self)
{
    EVP_PKEY *pkey;
    DH *dh;
    BIO *in;
    VALUE arg;

    GetPKey(self, pkey);
    /* The DH.new(size, generator) form is handled by lib/openssl/pkey.rb */
    if (rb_scan_args(argc, argv, "01", &arg) == 0) {
        dh = DH_new();
        if (!dh)
            ossl_raise(eDHError, "DH_new");
    }
    else {
	arg = ossl_to_der_if_possible(arg);
	in = ossl_obj2bio(&arg);
	dh = PEM_read_bio_DHparams(in, NULL, NULL, NULL);
	if (!dh){
	    OSSL_BIO_reset(in);
	    dh = d2i_DHparams_bio(in, NULL);
	}
	BIO_free(in);
	if (!dh) {
	    ossl_raise(eDHError, NULL);
	}
    }
    if (!EVP_PKEY_assign_DH(pkey, dh)) {
	DH_free(dh);
	ossl_raise(eDHError, NULL);
    }
    return self;
}

static VALUE
ossl_dh_initialize_copy(VALUE self, VALUE other)
{
    EVP_PKEY *pkey;
    DH *dh, *dh_other;
    const BIGNUM *pub, *priv;

    GetPKey(self, pkey);
    if (EVP_PKEY_base_id(pkey) != EVP_PKEY_NONE)
	ossl_raise(eDHError, "DH already initialized");
    GetDH(other, dh_other);

    dh = DHparams_dup(dh_other);
    if (!dh)
	ossl_raise(eDHError, "DHparams_dup");
    EVP_PKEY_assign_DH(pkey, dh);

    DH_get0_key(dh_other, &pub, &priv);
    if (pub) {
	BIGNUM *pub2 = BN_dup(pub);
	BIGNUM *priv2 = BN_dup(priv);

        if (!pub2 || (priv && !priv2)) {
	    BN_clear_free(pub2);
	    BN_clear_free(priv2);
	    ossl_raise(eDHError, "BN_dup");
	}
	DH_set0_key(dh, pub2, priv2);
    }

    return self;
}

/*
 *  call-seq:
 *     dh.public? -> true | false
 *
 * Indicates whether this DH instance has a public key associated with it or
 * not. The public key may be retrieved with DH#pub_key.
 */
static VALUE
ossl_dh_is_public(VALUE self)
{
    DH *dh;
    const BIGNUM *bn;

    GetDH(self, dh);
    DH_get0_key(dh, &bn, NULL);

    return bn ? Qtrue : Qfalse;
}

/*
 *  call-seq:
 *     dh.private? -> true | false
 *
 * Indicates whether this DH instance has a private key associated with it or
 * not. The private key may be retrieved with DH#priv_key.
 */
static VALUE
ossl_dh_is_private(VALUE self)
{
    DH *dh;
    const BIGNUM *bn;

    GetDH(self, dh);
    DH_get0_key(dh, NULL, &bn);

#if !defined(OPENSSL_NO_ENGINE)
    return (bn || DH_get0_engine(dh)) ? Qtrue : Qfalse;
#else
    return bn ? Qtrue : Qfalse;
#endif
}

/*
 *  call-seq:
 *     dh.export -> aString
 *     dh.to_pem -> aString
 *     dh.to_s -> aString
 *
 * Encodes this DH to its PEM encoding. Note that any existing per-session
 * public/private keys will *not* get encoded, just the Diffie-Hellman
 * parameters will be encoded.
 */
static VALUE
ossl_dh_export(VALUE self)
{
    DH *dh;
    BIO *out;
    VALUE str;

    GetDH(self, dh);
    if (!(out = BIO_new(BIO_s_mem()))) {
	ossl_raise(eDHError, NULL);
    }
    if (!PEM_write_bio_DHparams(out, dh)) {
	BIO_free(out);
	ossl_raise(eDHError, NULL);
    }
    str = ossl_membio2str(out);

    return str;
}

/*
 *  call-seq:
 *     dh.to_der -> aString
 *
 * Encodes this DH to its DER encoding. Note that any existing per-session
 * public/private keys will *not* get encoded, just the Diffie-Hellman
 * parameters will be encoded.

 */
static VALUE
ossl_dh_to_der(VALUE self)
{
    DH *dh;
    unsigned char *p;
    long len;
    VALUE str;

    GetDH(self, dh);
    if((len = i2d_DHparams(dh, NULL)) <= 0)
	ossl_raise(eDHError, NULL);
    str = rb_str_new(0, len);
    p = (unsigned char *)RSTRING_PTR(str);
    if(i2d_DHparams(dh, &p) < 0)
	ossl_raise(eDHError, NULL);
    ossl_str_adjust(str, p);

    return str;
}

/*
 *  call-seq:
 *     dh.params -> hash
 *
 * Stores all parameters of key to the hash
 * INSECURE: PRIVATE INFORMATIONS CAN LEAK OUT!!!
 * Don't use :-)) (I's up to you)
 */
static VALUE
ossl_dh_get_params(VALUE self)
{
    DH *dh;
    VALUE hash;
    const BIGNUM *p, *q, *g, *pub_key, *priv_key;

    GetDH(self, dh);
    DH_get0_pqg(dh, &p, &q, &g);
    DH_get0_key(dh, &pub_key, &priv_key);

    hash = rb_hash_new();
    rb_hash_aset(hash, rb_str_new2("p"), ossl_bn_new(p));
    rb_hash_aset(hash, rb_str_new2("q"), ossl_bn_new(q));
    rb_hash_aset(hash, rb_str_new2("g"), ossl_bn_new(g));
    rb_hash_aset(hash, rb_str_new2("pub_key"), ossl_bn_new(pub_key));
    rb_hash_aset(hash, rb_str_new2("priv_key"), ossl_bn_new(priv_key));

    return hash;
}

/*
 *  call-seq:
 *     dh.public_key -> aDH
 *
 * Returns a new DH instance that carries just the public information, i.e.
 * the prime _p_ and the generator _g_, but no public/private key yet. Such
 * a pair may be generated using DH#generate_key!. The "public key" needed
 * for a key exchange with DH#compute_key is considered as per-session
 * information and may be retrieved with DH#pub_key once a key pair has
 * been generated.
 * If the current instance already contains private information (and thus a
 * valid public/private key pair), this information will no longer be present
 * in the new instance generated by DH#public_key. This feature is helpful for
 * publishing the Diffie-Hellman parameters without leaking any of the private
 * per-session information.
 *
 * === Example
 *  dh = OpenSSL::PKey::DH.new(2048) # has public and private key set
 *  public_key = dh.public_key # contains only prime and generator
 *  parameters = public_key.to_der # it's safe to publish this
 */
static VALUE
ossl_dh_to_public_key(VALUE self)
{
    EVP_PKEY *pkey;
    DH *orig_dh, *dh;
    VALUE obj;

    obj = rb_obj_alloc(rb_obj_class(self));
    GetPKey(obj, pkey);

    GetDH(self, orig_dh);
    dh = DHparams_dup(orig_dh);
    if (!dh)
        ossl_raise(eDHError, "DHparams_dup");
    if (!EVP_PKEY_assign_DH(pkey, dh)) {
        DH_free(dh);
        ossl_raise(eDHError, "EVP_PKEY_assign_DH");
    }
    return obj;
}

/*
 *  call-seq:
 *     dh.params_ok? -> true | false
 *
 * Validates the Diffie-Hellman parameters associated with this instance.
 * It checks whether a safe prime and a suitable generator are used. If this
 * is not the case, +false+ is returned.
 */
static VALUE
ossl_dh_check_params(VALUE self)
{
    DH *dh;
    int codes;

    GetDH(self, dh);
    if (!DH_check(dh, &codes)) {
	return Qfalse;
    }

    return codes == 0 ? Qtrue : Qfalse;
}

/*
 * Document-method: OpenSSL::PKey::DH#set_pqg
 * call-seq:
 *   dh.set_pqg(p, q, g) -> self
 *
 * Sets _p_, _q_, _g_ to the DH instance.
 */
OSSL_PKEY_BN_DEF3(dh, DH, pqg, p, q, g)
/*
 * Document-method: OpenSSL::PKey::DH#set_key
 * call-seq:
 *   dh.set_key(pub_key, priv_key) -> self
 *
 * Sets _pub_key_ and _priv_key_ for the DH instance. _priv_key_ may be +nil+.
 */
OSSL_PKEY_BN_DEF2(dh, DH, key, pub_key, priv_key)

/*
 * INIT
 */
void
Init_ossl_dh(void)
{
#if 0
    mPKey = rb_define_module_under(mOSSL, "PKey");
    cPKey = rb_define_class_under(mPKey, "PKey", rb_cObject);
    ePKeyError = rb_define_class_under(mPKey, "PKeyError", eOSSLError);
#endif

    /* Document-class: OpenSSL::PKey::DHError
     *
     * Generic exception that is raised if an operation on a DH PKey
     * fails unexpectedly or in case an instantiation of an instance of DH
     * fails due to non-conformant input data.
     */
    eDHError = rb_define_class_under(mPKey, "DHError", ePKeyError);
    /* Document-class: OpenSSL::PKey::DH
     *
     * An implementation of the Diffie-Hellman key exchange protocol based on
     * discrete logarithms in finite fields, the same basis that DSA is built
     * on.
     *
     * === Accessor methods for the Diffie-Hellman parameters
     * DH#p::
     *   The prime (an OpenSSL::BN) of the Diffie-Hellman parameters.
     * DH#g::
     *   The generator (an OpenSSL::BN) g of the Diffie-Hellman parameters.
     * DH#pub_key::
     *   The per-session public key (an OpenSSL::BN) matching the private key.
     *   This needs to be passed to DH#compute_key.
     * DH#priv_key::
     *   The per-session private key, an OpenSSL::BN.
     *
     * === Example of a key exchange
     *  dh1 = OpenSSL::PKey::DH.new(2048)
     *  der = dh1.public_key.to_der #you may send this publicly to the participating party
     *  dh2 = OpenSSL::PKey::DH.new(der)
     *  dh2.generate_key! #generate the per-session key pair
     *  symm_key1 = dh1.compute_key(dh2.pub_key)
     *  symm_key2 = dh2.compute_key(dh1.pub_key)
     *
     *  puts symm_key1 == symm_key2 # => true
     */
    cDH = rb_define_class_under(mPKey, "DH", cPKey);
    rb_define_method(cDH, "initialize", ossl_dh_initialize, -1);
    rb_define_method(cDH, "initialize_copy", ossl_dh_initialize_copy, 1);
    rb_define_method(cDH, "public?", ossl_dh_is_public, 0);
    rb_define_method(cDH, "private?", ossl_dh_is_private, 0);
    rb_define_method(cDH, "export", ossl_dh_export, 0);
    rb_define_alias(cDH, "to_pem", "export");
    rb_define_alias(cDH, "to_s", "export");
    rb_define_method(cDH, "to_der", ossl_dh_to_der, 0);
    rb_define_method(cDH, "public_key", ossl_dh_to_public_key, 0);
    rb_define_method(cDH, "params_ok?", ossl_dh_check_params, 0);

    DEF_OSSL_PKEY_BN(cDH, dh, p);
    DEF_OSSL_PKEY_BN(cDH, dh, q);
    DEF_OSSL_PKEY_BN(cDH, dh, g);
    DEF_OSSL_PKEY_BN(cDH, dh, pub_key);
    DEF_OSSL_PKEY_BN(cDH, dh, priv_key);
    rb_define_method(cDH, "set_pqg", ossl_dh_set_pqg, 3);
    rb_define_method(cDH, "set_key", ossl_dh_set_key, 2);

    rb_define_method(cDH, "params", ossl_dh_get_params, 0);
}

#else /* defined NO_DH */
void
Init_ossl_dh(void)
{
}
#endif /* NO_DH */
