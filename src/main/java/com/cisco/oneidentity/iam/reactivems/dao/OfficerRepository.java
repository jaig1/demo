package com.cisco.oneidentity.iam.reactivems.dao;

import org.springframework.data.repository.query.Param;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;

import com.cisco.oneidentity.iam.reactivems.entities.Officer;
import com.cisco.oneidentity.iam.reactivems.entities.Rank;

import reactor.core.publisher.Flux;

public interface OfficerRepository extends ReactiveCrudRepository<Officer, String> {
    Flux<Officer> findByRank(@Param("rank") Rank rank);
    Flux<Officer> findByLast(@Param("last") String last);
}